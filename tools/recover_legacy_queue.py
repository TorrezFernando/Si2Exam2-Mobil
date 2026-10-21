"""Import explicitly verified legacy operations into an initialized account database.

Never alters the source. The mapping is an operator-reviewed JSON list, not inferred
from the unreliable v2 queue defaults. Run with the app closed and keep a backup.
"""
import argparse
import json
import sqlite3
from pathlib import Path


def recover(source, target, assignments):
    source, target = Path(source).resolve(), Path(target).resolve()
    if source == target or not source.is_file() or not target.is_file():
        raise ValueError('Source and initialized target must be different existing files.')
    if not assignments:
        raise ValueError('An explicit reviewed assignment list is required.')
    contexts = {(r['tenant_id'], r['owner_id']) for r in assignments}
    if len(contexts) != 1:
        raise ValueError('One verified account per import.')
    tenant, owner = contexts.pop()
    if tenant <= 0 or owner <= 0 or target.name != f'fashionstore_account_{tenant}_{owner}.db':
        raise ValueError('Destination filename does not match the verified account.')
    src = sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)
    dst = sqlite3.connect(target)
    src.row_factory = dst.row_factory = sqlite3.Row
    try:
        if dst.execute('PRAGMA user_version').fetchone()[0] != 3:
            raise ValueError('Open the new app with this account first to initialize schema v3.')
        dst.execute('PRAGMA foreign_keys=ON')
        def insert(table, row):
            columns = {r['name'] for r in dst.execute(f'PRAGMA table_info({table})')}
            values = {k:v for k,v in row.items() if k in columns}
            dst.execute(f"INSERT INTO {table} ({','.join(values)}) VALUES ({','.join('?' for _ in values)})",list(values.values()))
        with dst:
            for assignment in assignments:
                if assignment.get('verified') is not True:
                    raise ValueError('Every ownership assignment must be explicitly verified.')
                uid = assignment['client_operation_uuid']
                old = src.execute('SELECT * FROM sync_operations WHERE client_operation_uuid=?',(uid,)).fetchone()
                if not old: raise ValueError('Legacy operation missing: '+uid)
                op = dict(old)
                kind = op['operation_type']
                if kind not in ('sale','reservation'): raise ValueError('Unknown operation type.')
                table, items_table = ('sales','sale_items') if kind=='sale' else ('reservations','reservation_items')
                header = dict(src.execute(f'SELECT * FROM {table} WHERE client_operation_uuid=?',(uid,)).fetchone())
                branch = assignment['branch_id']
                if header['branch_id'] != branch or header['user_id'] != assignment['customer_id']:
                    raise ValueError('Verified branch/customer must match the original header, not migrated queue defaults.')
                if header.get('tenant_id') not in (None, tenant) and not assignment.get('verified_legacy_tenant_error'):
                    raise ValueError('Tenant discrepancy requires explicit review of the legacy tenant error.')
                existing = dst.execute('SELECT payload FROM sync_operations WHERE client_operation_uuid=?',(uid,)).fetchone()
                if existing:
                    if json.loads(existing['payload']) != json.loads(op['payload']): raise ValueError('Existing UUID has different payload.')
                    continue
                if not dst.execute('SELECT id FROM branches WHERE id=?',(branch,)).fetchone():
                    insert('branches',dict(id=branch,tenant_id=tenant,name=f'Sucursal histórica {branch}',address='',is_active=0))
                items = [dict(r) for r in src.execute(f'SELECT * FROM {items_table} WHERE client_operation_uuid=?',(uid,))]
                for item in items:
                    vid=item['variant_id']
                    if not dst.execute('SELECT id FROM variants WHERE id=?',(vid,)).fetchone():
                        variant=src.execute('SELECT * FROM variants WHERE id=?',(vid,)).fetchone()
                        if not variant: raise ValueError('Missing historical variant; restore its catalog before importing.')
                        variant=dict(variant)
                        if not dst.execute('SELECT id FROM products WHERE id=?',(variant['product_id'],)).fetchone():
                            product=dict(src.execute('SELECT * FROM products WHERE id=?',(variant['product_id'],)).fetchone())
                            product.update(tenant_id=tenant,is_active=0);insert('products',product)
                        variant['stock']=0;insert('variants',variant)
                state='PENDIENTE' if op['status'] in ('PENDIENTE','ENVIANDO') else op['status']
                header.update(tenant_id=tenant,sync_status=state);insert(table,header)
                for item in items:
                    item.pop('id',None);insert(items_table,item)
                op.update(tenant_id=tenant,user_id=owner,branch_id=branch,status=state,blocked=0,next_retry_at=None,
                    sale_uuid=uid if kind=='sale' else None,reservation_uuid=uid if kind=='reservation' else None)
                insert('sync_operations',op)
            # An imported pending operation may already be present in remote stock.
            # Disable local trading until its receipt is reconciled and snapshot refreshed.
            dst.execute('DELETE FROM cache_metadata')
            if dst.execute('PRAGMA foreign_key_check').fetchall(): raise ValueError('Invalid references; import rolled back.')
    finally:
        src.close();dst.close()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True)
    parser.add_argument('--target',required=True)
    parser.add_argument('--assignments',required=True)
    args=parser.parse_args()
    recover(args.source,args.target,json.loads(Path(args.assignments).read_text(encoding='utf-8')))
    print('Import completed. Reconcile receipts, then refresh the catalog before trading.')
