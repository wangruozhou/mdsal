/*
 * Copyright (c) 2013 Cisco Systems, Inc. and others.  All rights reserved.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 */
package org.opendaylight.controller.sal.binding.codegen.impl

import java.util.Map
import java.util.WeakHashMap
import javassist.ClassPool
import javassist.CtClass
import javassist.CtMethod
import javassist.LoaderClassPath
import org.opendaylight.controller.sal.binding.spi.NotificationInvokerFactory
import org.opendaylight.yangtools.sal.binding.generator.util.JavassistUtils
import org.opendaylight.yangtools.yang.binding.DataContainer
import org.opendaylight.yangtools.yang.binding.InstanceIdentifier
import org.opendaylight.yangtools.yang.binding.Notification
import org.opendaylight.yangtools.yang.binding.NotificationListener
import org.opendaylight.yangtools.yang.binding.RpcImplementation
import org.opendaylight.yangtools.yang.binding.RpcService
import org.opendaylight.yangtools.yang.binding.annotations.RoutingContext
import org.opendaylight.yangtools.yang.binding.util.ClassLoaderUtils

import static extension org.opendaylight.controller.sal.binding.codegen.RuntimeCodeSpecification.*
import static extension org.opendaylight.controller.sal.binding.codegen.YangtoolsMappingHelper.*

class RuntimeCodeGenerator implements org.opendaylight.controller.sal.binding.codegen.RuntimeCodeGenerator, NotificationInvokerFactory {

    val CtClass BROKER_NOTIFICATION_LISTENER;
    val extension JavassistUtils utils;
    val Map<Class<? extends NotificationListener>, RuntimeGeneratedInvokerPrototype> invokerClasses;


    new(ClassPool pool) {
        utils = new JavassistUtils(pool);
        invokerClasses = new WeakHashMap();
        BROKER_NOTIFICATION_LISTENER = org.opendaylight.controller.sal.binding.api.NotificationListener.asCtClass;
        pool.appendClassPath(new LoaderClassPath(RpcService.classLoader));
    }

    override <T extends RpcService> getDirectProxyFor(Class<T> iface) {
        val T instance = ClassLoaderUtils.withClassLoaderAndLock(iface.classLoader,lock) [|
            val proxyName = iface.directProxyName;
            val potentialClass = ClassLoaderUtils.tryToLoadClassWithTCCL(proxyName)
            if(potentialClass != null) {
                return potentialClass.newInstance as T;
            }
            val supertype = iface.asCtClass
            val createdCls = createClass(iface.directProxyName, supertype) [
                field(DELEGATE_FIELD, iface);
                implementsType(RpcImplementation.asCtClass)
                implementMethodsFrom(supertype) [
                    body = '''
                    {
                        if(«DELEGATE_FIELD» == null) {
                            throw new java.lang.IllegalStateException("No default provider is available");
                        }
                        return ($r) «DELEGATE_FIELD».«it.name»($$);
                    }
                    '''
                ]
                implementMethodsFrom(RpcImplementation.asCtClass) [
                    body = '''
                    {
                        throw new java.lang.IllegalStateException("No provider is processing supplied message");
                        return ($r) null;
                    }
                    '''
                ]
            ]
            return createdCls.toClass(iface.classLoader).newInstance as T
        ]
        return instance;
    }

    override <T extends RpcService> getRouterFor(Class<T> iface,String routerInstanceName) {
        val metadata = ClassLoaderUtils.withClassLoader(iface.classLoader) [|
            val supertype = iface.asCtClass
            return supertype.rpcMetadata;
        ]

        val instance = ClassLoaderUtils.<T>withClassLoaderAndLock(iface.classLoader,lock) [ |
            val supertype = iface.asCtClass
            val routerName = iface.routerName;
            val potentialClass = ClassLoaderUtils.tryToLoadClassWithTCCL(routerName)
            if(potentialClass != null) {
                return potentialClass.newInstance as T;
            }

            val targetCls = createClass(iface.routerName, supertype) [


                field(DELEGATE_FIELD, iface)
                //field(REMOTE_INVOKER_FIELD,iface);
                implementsType(RpcImplementation.asCtClass)

                for (ctx : metadata.contexts) {
                    field(ctx.routingTableField, Map)
                }
                implementMethodsFrom(supertype) [
                    if (parameterTypes.size === 1) {
                        val rpcMeta = metadata.rpcMethods.get(name);
                        val bodyTmp = '''
                        {
                            final «InstanceIdentifier.name» identifier = $1.«rpcMeta.inputRouteGetter.name»()«IF rpcMeta.
                            routeEncapsulated».getValue()«ENDIF»;
                            «supertype.name» instance = («supertype.name») «rpcMeta.context.routingTableField».get(identifier);
                            if(instance == null) {
                               instance = «DELEGATE_FIELD»;
                            }
                            if(instance == null) {
                                throw new java.lang.IllegalStateException("No routable provider is processing routed message for " + String.valueOf(identifier));
                            }
                            return ($r) instance.«it.name»($$);
                        }'''
                        body = bodyTmp
                    } else if (parameterTypes.size === 0) {
                        body = '''return ($r) «DELEGATE_FIELD».«it.name»($$);'''
                    }
                ]
                implementMethodsFrom(RpcImplementation.asCtClass) [
                    body = '''
                    {
                        throw new java.lang.IllegalStateException("No provider is processing supplied message");
                        return ($r) null;
                    }
                    '''
                ]
            ]
            return targetCls.toClass(iface.classLoader,iface.protectionDomain).newInstance as T

        ];
        return new RpcRouterCodegenInstance(routerInstanceName,iface, instance, metadata.contexts,metadata.supportedInputs);
    }

    private def RpcServiceMetadata getRpcMetadata(CtClass iface) {
        val metadata = new RpcServiceMetadata;

        iface.methods.filter[declaringClass == iface && parameterTypes.size === 1].forEach [ method |
            val routingPair = method.rpcMetadata;
            if (routingPair !== null) {
                metadata.contexts.add(routingPair.context)
                metadata.rpcMethods.put(method.name,routingPair)
                val input = routingPair.inputType.javaClass as Class<? extends DataContainer>;
                metadata.supportedInputs.add(input);
                metadata.rpcInputs.put(input,routingPair);
            }
        ]
        return metadata;
    }

    private def getRpcMetadata(CtMethod method) {
        val inputClass = method.parameterTypes.get(0);
        return inputClass.rpcMethodMetadata(inputClass,method.name);
    }

    private def RpcMetadata rpcMethodMetadata(CtClass dataClass, CtClass inputClass, String rpcMethod) {
        for (method : dataClass.methods) {
            if (method.name.startsWith("get") && method.parameterTypes.size === 0) {
                for (annotation : method.availableAnnotations) {
                    if (annotation instanceof RoutingContext) {
                        val encapsulated = !method.returnType.equals(InstanceIdentifier.asCtClass);
                        return new RpcMetadata(rpcMethod,(annotation as RoutingContext).value, method, encapsulated,inputClass);
                    }
                }
            }
        }
        for (iface : dataClass.interfaces) {
            val ret = rpcMethodMetadata(iface,inputClass,rpcMethod);
            if(ret != null) return ret;
        }
        return null;
    }

    private def getJavaClass(CtClass cls) {
        Thread.currentThread.contextClassLoader.loadClass(cls.name)
    }

    override getInvokerFactory() {
        return this;
    }

    override invokerFor(NotificationListener instance) {
        val cls = instance.class
        val prototype = resolveInvokerClass(cls);

        return RuntimeGeneratedInvoker.create(instance, prototype)
    }

    protected def generateListenerInvoker(Class<? extends NotificationListener> iface) {
        val callbacks = iface.methods.filter[notificationCallback]

        val supportedNotification = callbacks.map[parameterTypes.get(0) as Class<? extends Notification>].toSet;

        val targetCls = createClass(iface.invokerName, BROKER_NOTIFICATION_LISTENER) [
            field(DELEGATE_FIELD, iface)
            implementMethodsFrom(BROKER_NOTIFICATION_LISTENER) [
                body = '''
                    {
                        «FOR callback : callbacks SEPARATOR " else "»
                            «val cls = callback.parameterTypes.get(0).name»
                                if($1 instanceof «cls») {
                                    «DELEGATE_FIELD».«callback.name»((«cls») $1);
                                    return null;
                                }
                        «ENDFOR»
                        return null;
                    }
                '''
            ]
        ]
        val finalClass = targetCls.toClass(iface.classLoader, iface.protectionDomain)
        return new RuntimeGeneratedInvokerPrototype(supportedNotification,
            finalClass as Class<? extends org.opendaylight.controller.sal.binding.api.NotificationListener<?>>);
    }

    protected def resolveInvokerClass(Class<? extends NotificationListener> class1) {
        return ClassLoaderUtils.<RuntimeGeneratedInvokerPrototype>withClassLoaderAndLock(class1.classLoader,lock) [|
            val invoker = invokerClasses.get(class1);
            if (invoker !== null) {
                return invoker;
            }
            val newInvoker = generateListenerInvoker(class1);
            invokerClasses.put(class1, newInvoker);
            return newInvoker
        ]
    }
}
