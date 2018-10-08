/*
 * Copyright © 2018 Red Hat, Inc. and others.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 */
package org.opendaylight.mdsal.binding.util;

import org.opendaylight.mdsal.binding.api.WriteTransaction;
import org.opendaylight.yangtools.yang.binding.DataObject;
import org.opendaylight.yangtools.yang.binding.InstanceIdentifier;

/**
 * Implementation of {@link TypedWriteTransaction}.
 *
 * @param <D> The datastore which the transaction targets.
 */
class TypedWriteTransactionImpl<D extends Datastore> extends TypedTransaction<D>
        implements TypedWriteTransaction<D> {
    // Temporarily package protected for TransactionAdapter
    final WriteTransaction delegate;

    TypedWriteTransactionImpl(final Class<D> datastoreType, final WriteTransaction realTx) {
        super(datastoreType);
        this.delegate = realTx;
    }

    @Override
    public <T extends DataObject> void put(final InstanceIdentifier<T> path, final T data) {
        delegate.put(getDatastoreType(), path, data);
    }

    @Override
    public <T extends DataObject> void put(final InstanceIdentifier<T> path, final T data,
            final boolean createMissingParents) {
        delegate.put(getDatastoreType(), path, data, createMissingParents);
    }

    @Override
    public <T extends DataObject> void merge(final InstanceIdentifier<T> path, final T data) {
        delegate.merge(getDatastoreType(), path, data);
    }

    @Override
    public <T extends DataObject> void merge(final InstanceIdentifier<T> path, final T data,
            final boolean createMissingParents) {
        delegate.merge(getDatastoreType(), path, data, createMissingParents);
    }

    @Override
    public void delete(final InstanceIdentifier<?> path) {
        delegate.delete(getDatastoreType(), path);
    }

    @Override
    public Object getIdentifier() {
        return delegate.getIdentifier();
    }
}
