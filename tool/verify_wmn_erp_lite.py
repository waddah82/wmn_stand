import json, pathlib, hashlib, zipfile, re, sqlite3, uuid, datetime, sys
ROOT=pathlib.Path(__file__).resolve().parent.parent
APP=ROOT/'applications'/'wmn_erp_lite'
META=APP/'metadata'; DIST=APP/'dist'
COMPONENTS=['modules','doctypes','doctype_fields','doctype_permissions','list_views','custom_fields','property_overrides','numbering_series','roles','permissions','role_permissions','workspaces','workspace_items','pages','reports','report_filters','report_columns','print_formats','client_scripts','server_scripts','workflows','workflow_states','workflow_transitions','method_bindings','hook_bindings','number_cards','dashboard_charts']
errors=[]; checks=[]
def ok(msg): checks.append(msg)
def err(msg): errors.append(msg)
def load(p): return json.loads(pathlib.Path(p).read_text(encoding='utf-8'))
manifest=load(APP/'manifest.json'); profile=load(APP/'profile.json')
components={k:load(META/f'{k}.json') for k in COMPONENTS}
source_map=load(APP/'sources/index.json')
app=manifest['name']; modules=set(manifest['modules']); doctypes={d['name']:d for d in components['doctypes']}; reports={r['report_name']:r for r in components['reports']}
if manifest.get('version') != '1.3.0': err(f"Expected ERP Lite 1.3.0, found {manifest.get('version')}")
# JSON / counts
for k,v in components.items():
    if not isinstance(v,list): err(f'{k} is not an array')
ok(f'Loaded {len(COMPONENTS)} metadata component files')
if len(doctypes)!=len(components['doctypes']): err('Duplicate DocType names')
if len({f['id'] for f in components['doctype_fields']})!=len(components['doctype_fields']): err('Duplicate DocType field ids')
# Match the platform MetaService contract: a hidden mandatory field must have a default.
for f in components['doctype_fields']:
    hidden=int(f.get('hidden') or 0)==1; mandatory=int(f.get('reqd') or 0)==1
    default=f.get('default_json')
    if hidden and mandatory and default in (None, ''):
        err(f"{f['doctype']}.{f['fieldname']} cannot be hidden and mandatory without a default")
ok('Hidden/mandatory/default metadata contract matches platform MetaService')
# Payment allocation updates invoice outstanding after submit; these fields must remain system-managed and allow_on_submit.
field_index={(f.get('doctype'),f.get('fieldname')):f for f in components['doctype_fields']}
for dt in ['Sales Invoice','Purchase Invoice','POS Invoice']:
    f=field_index.get((dt,'outstanding_amount'))
    if not f:
        err(f'{dt}.outstanding_amount metadata is missing')
        continue
    if int(f.get('read_only') or 0)!=1:
        err(f'{dt}.outstanding_amount must remain read-only/system-maintained')
    if int(f.get('allow_on_submit') or 0)!=1:
        err(f'{dt}.outstanding_amount must allow system updates after submit')
ok('Submitted invoice outstanding fields are read-only and allow_on_submit for payment allocation')
# ownership
for m in components['modules']:
    if m.get('app_name')!=app: err(f"Module owner mismatch: {m.get('name')}")
    if m.get('name') not in modules: err(f"Module not declared in manifest: {m.get('name')}")
for d in components['doctypes']:
    if d.get('module') not in modules: err(f"DocType outside app modules: {d['name']}")
    if int(d.get('is_system') or 0): err(f"System DocType packaged: {d['name']}")
ok('Application ownership checks complete')
# refs
for f in components['doctype_fields']:
    if f['doctype'] not in doctypes: err(f"Field parent missing: {f['id']}")
    t=f.get('fieldtype'); opt=(f.get('options') or '').strip()
    if t in {'Link','Table'} and opt and opt not in doctypes:
        err(f"Unknown {t} target {opt} from {f['doctype']}.{f['fieldname']}")
for r in components['reports']:
    if r.get('module') not in modules: err(f"Report module invalid: {r['report_name']}")
    if r.get('ref_doctype') and r['ref_doctype'] not in doctypes: err(f"Report ref DocType missing: {r['report_name']}")
for route in manifest.get('route_definitions',[]):
    typ=route.get('target_type'); target=route.get('target')
    if typ=='doctype' and target not in doctypes: err(f'Route DocType missing: {target}')
    if typ=='report' and target not in reports: err(f'Route report missing: {target}')
    if typ=='page' and target not in {p['name'] for p in components['pages']}: err(f'Route Page missing: {target}')
ok('DocType, report and Page route references complete')
# Workspace-first application contract
workspace_names={w['name'] for w in components['workspaces']}
expected_workspaces={'WMN ERP Lite - Accounting','WMN ERP Lite - Stock','WMN ERP Lite - Buying','WMN ERP Lite - Selling','WMN ERP Lite - Point of Sale'}
if workspace_names != expected_workspaces: err(f'Workspace set mismatch: {sorted(workspace_names)}')
if set(manifest.get('workspaces') or []) != expected_workspaces: err('Manifest workspace declarations do not match workspace metadata')
if manifest.get('minimum_platform_version') != '3.24.0': err('ERP Lite 1.3.0 requires WMN 3.24.0 generic transaction workspace runtime')
if any(r.get('show_in_navigation', True) for r in manifest.get('route_definitions', [])): err('ERP Lite routes must remain hidden from global Application Navigation; Workspaces are the primary UI')
for wi in components['workspace_items']:
    if wi.get('parent') not in workspace_names: err(f'Workspace Item parent missing: {wi.get("name")}')
    if wi.get('parenttype')!='Workspace' or wi.get('parentfield')!='items': err(f'Workspace Item child-table contract invalid: {wi.get("name")}')
    lt=(wi.get('link_type') or '').lower(); target=wi.get('link_to')
    if lt=='doctype' and target not in doctypes: err(f'Workspace Item DocType target missing: {target}')
    if lt=='report' and target not in {r['report_name'] for r in components['reports']}: err(f'Workspace Item Report target missing: {target}')
    if wi.get('region')=='NUMBER_CARDS' and target not in {c['name'] for c in components['number_cards']}: err(f'Workspace number card target missing: {target}')
# Link-card and application-owned transactional Page contract.
page_names={p['name'] for p in components['pages']}
if set(manifest.get('pages') or []) != page_names: err('Manifest Page declarations do not match Page metadata')
if page_names != {'WMN ERP Lite POS'}: err(f'ERP Lite POS Page set mismatch: {sorted(page_names)}')
pos_page=next((p for p in components['pages'] if p.get('name')=='WMN ERP Lite POS'),None)
if not pos_page: err('WMN ERP Lite POS Page is missing')
else:
    if pos_page.get('page_type')!='CUSTOM': err('ERP Lite POS Page must be CUSTOM')
    if pos_page.get('controller_key')!='wmn.page.transaction_workspace_v1': err('ERP Lite POS Page must use the generic transaction workspace controller')
    try: page_meta=json.loads(pos_page.get('metadata_json') or '{}')
    except Exception as e: err(f'ERP Lite POS Page metadata_json invalid: {e}'); page_meta={}
    if page_meta.get('runtime_contract')!='wmn.transaction-workspace-v1': err('ERP Lite POS runtime_contract mismatch')
    required_resources={
        'transaction_doctype':'POS Invoice','profile_doctype':'POS Profile','product_doctype':'Item','party_doctype':'Customer',
        'payment_method_doctype':'Mode of Payment','session_open_doctype':'POS Opening Entry','session_close_doctype':'POS Closing Entry',
        'product_group_doctype':'Item Group','price_doctype':'Item Price','availability_doctype':'Bin',
    }
    for key,expected in required_resources.items():
        if page_meta.get(key)!=expected: err(f'ERP Lite POS Page {key} must be {expected}')
    required_mappings={
        'field_transaction_lines':'items','field_transaction_payments':'payments','field_line_product':'item_code',
        'field_profile_print_format':'print_format_id','field_profile_payment_table':'payment_modes',
        'field_session_closing_link':'closing_entry','field_closing_session_link':'pos_opening_entry',
    }
    for key,expected in required_mappings.items():
        if page_meta.get(key)!=expected: err(f'ERP Lite POS Page mapping {key} must be {expected}')
    if int(page_meta.get('require_open_session') or 0)!=1: err('ERP Lite POS Page must require an open session')
    if int(page_meta.get('update_inventory') or 0)!=1: err('ERP Lite POS Page must update inventory')
# ERPNext-style POS v2 metadata must include shift, return, tender and profile configuration contracts.
required_pos_doctypes={'POS Profile Payment','POS Opening Entry','POS Opening Balance','POS Closing Entry','POS Closing Detail'}
missing_pos_doctypes=required_pos_doctypes.difference(doctypes)
if missing_pos_doctypes: err(f'POS v2 DocTypes missing: {sorted(missing_pos_doctypes)}')
required_pos_invoice_fields={'pos_opening_entry','pos_status','is_return','return_against','tendered_amount','change_amount','allow_partial_payment','refunded_amount'}
missing_pos_invoice_fields={name for name in required_pos_invoice_fields if ('POS Invoice',name) not in field_index}
if missing_pos_invoice_fields: err(f'POS Invoice v2 fields missing: {sorted(missing_pos_invoice_fields)}')
required_profile_fields={'payment_modes','hide_unavailable_items','allow_edit_rate','allow_edit_discount','auto_add_filtered_item','validate_stock','set_grand_total_to_default_payment','print_receipt_on_complete','allow_partial_payment','allow_returns','action_on_new_invoice','item_group','currency','selling_price_list','print_format_id'}
missing_profile_fields={name for name in required_profile_fields if ('POS Profile',name) not in field_index}
if missing_profile_fields: err(f'POS Profile v2 fields missing: {sorted(missing_profile_fields)}')
for item_field in ['barcode','image','is_stock_item']:
    if ('Item',item_field) not in field_index: err(f'Item.{item_field} is required by POS v2')
if ('POS Invoice Item','is_stock_item') not in field_index: err('POS Invoice Item.is_stock_item is required so service items never post stock')
required_pos_scripts={'pos_profile_validate','pos_opening_validate','pos_opening_cancel','pos_closing_validate','pos_closing_submit','pos_closing_cancel'}
script_ids={s.get('id') for s in components['server_scripts']}
missing_pos_scripts=required_pos_scripts.difference(script_ids)
if missing_pos_scripts: err(f'POS shift scripts missing: {sorted(missing_pos_scripts)}')
# Closing cancel must unlink POS Opening Entry before generic DocumentService incoming-link validation.
closing_hook=next((h for h in components['hook_bindings'] if h.get('id')=='hook-pos_closing_cancel'),None)
closing_script=next((s for s in components['server_scripts'] if s.get('id')=='pos_closing_cancel'),None)
if not closing_hook or closing_hook.get('event_name')!='before_cancel': err('POS Closing cancel hook must run on before_cancel to clear Opening Entry.closing_entry before incoming-link validation')
if not closing_script or closing_script.get('event_name')!='before_cancel': err('POS Closing cancel Server Script must declare before_cancel')
else: ok('POS Closing cancellation unlinks the Opening Entry before generic incoming-link validation')
if 'mobile.scanner' not in set(manifest.get('optional_capabilities') or []): err('ERP Lite POS must declare mobile.scanner as an optional capability')
refunded=field_index.get(('POS Invoice','refunded_amount'))
if refunded and (int(refunded.get('read_only') or 0)!=1 or int(refunded.get('allow_on_submit') or 0)!=1):
    err('POS Invoice.refunded_amount must be read-only and allow_on_submit for cumulative refund accounting')
card_items=[wi for wi in components['workspace_items'] if (wi.get('parent_label') or '').strip()]
if len(card_items)!=71: err(f'Expected 71 Workspace Link Card items, found {len(card_items)}')
for wi in components['workspace_items']:
    if wi.get('region') in {'SHORTCUTS','LINKS'} and not (wi.get('parent_label') or '').strip():
        err(f'Workspace shortcut/link must belong to a Link Card: {wi.get("name")}')
pos_shortcuts=[wi for wi in components['workspace_items'] if wi.get('parent')=='WMN ERP Lite - Point of Sale' and (wi.get('link_type') or '').lower()=='page']
if len(pos_shortcuts)!=1 or pos_shortcuts[0].get('link_to')!='WMN ERP Lite POS': err('Point of Sale Workspace must expose the interactive POS Page exactly once')
ok(f"Workspace-first contract validated: {len(workspace_names)} Workspaces / {len(components['workspace_items'])} Workspace Items / {len(card_items)} Link Card items / {len(page_names)} Page")

# POS and print metadata contracts.
pos_payments=field_index.get(('POS Invoice','payments'))
if not pos_payments: err('POS Invoice.payments field is missing')
elif int(pos_payments.get('reqd') or 0)!=0: err('POS Invoice.payments must not be mandatory so credit POS can follow the managed allow_credit validation')
qr_sizes={}
for pf in components['print_formats']:
    if pf.get('document_type') not in {'Sales Invoice','Purchase Invoice','POS Invoice'}: continue
    try: meta=json.loads(pf.get('metadata_json') or '{}')
    except Exception as e: err(f"Invalid Print Format metadata_json for {pf.get('name')}: {e}"); continue
    size=meta.get('qr_size_mm')
    if not isinstance(size,(int,float)) or not 12 <= float(size) <= 25: err(f"Print Format QR size must be 12..25 mm: {pf.get('name')}={size}")
    else: qr_sizes[pf.get('document_type')]=float(size)
if set(qr_sizes)!={'Sales Invoice','Purchase Invoice','POS Invoice'}: err(f'Missing physical QR sizing for invoice Print Formats: {qr_sizes}')
ok(f'POS payment and physical invoice QR metadata contracts validated: {qr_sizes}')

# intentionally excluded features
for k in ['roles','permissions','role_permissions','workflows','workflow_states','workflow_transitions']:
    if components[k]: err(f'Lite v1 must not package {k}')
ok('Excluded multi-user governance engines are absent')
# engine-owned protection
for name in ['GL Entry','Payment Ledger Entry','Bin','Stock Ledger Entry','Stock Posting Snapshot']:
    d=doctypes.get(name)
    if not d: err(f'Engine DocType missing: {name}'); continue
    for key in ['generic_write','allow_create','allow_edit','allow_delete']:
        if int(d.get(key) or 0)!=0: err(f'{name}.{key} must be 0')
ok('Engine-owned ledger/cache DocTypes are protected from generic writes')
# source index
storage_keys=set(); files=set()
for row in source_map:
    sk=row.get('storage_key',''); rel=row.get('file','')
    if not sk.startswith(f'apps/{app}/'): err(f'Unowned source storage path: {sk}')
    if sk in storage_keys: err(f'Duplicate storage key: {sk}')
    storage_keys.add(sk)
    if rel in files: err(f'Duplicate editable source path: {rel}')
    files.add(rel)
    if not (APP/rel).is_file(): err(f'Missing editable source file: {rel}')
for s in components['server_scripts']:
    if s.get('source_storage_path') not in storage_keys: err(f"Server script source missing: {s['id']}")
for r in components['reports']:
    if r.get('query_source_type')=='STORAGE_FILE' and r.get('query_source_path') not in storage_keys: err(f"Report source missing: {r['report_name']}")
ok(f'Validated {len(source_map)} managed source mappings')
# Report storage contract must match schema v36 exactly.
allowed_query_source_types={'INLINE','STORAGE_FILE','STRUCTURED'}
allowed_script_source_types={'NATIVE_HANDLER','STORAGE_FILE'}
for r in components['reports']:
    qst=r.get('query_source_type')
    sst=r.get('script_source_type')
    if qst not in allowed_query_source_types: err(f"Invalid Report.query_source_type {qst!r}: {r.get('report_name')}")
    if sst not in allowed_script_source_types: err(f"Invalid Report.script_source_type {sst!r}: {r.get('report_name')}")
    if r.get('report_type')=='Query Report' and qst!='STORAGE_FILE': err(f"Query Report must use STORAGE_FILE: {r.get('report_name')}")
ok('Report source-type values match schema v36 CHECK constraints')
# Insert report rows into the exact v36 reference tabReport table to catch DB CHECK violations before delivery.
ref_db=ROOT/'database/reference/wmn_platform_schema_v36.sqlite3'
if not ref_db.is_file():
    err('Missing schema v36 reference database for metadata constraint validation')
else:
    chk=sqlite3.connect(':memory:')
    ref=sqlite3.connect(str(ref_db))
    schema_sql=ref.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='tabReport'").fetchone()
    if not schema_sql or not schema_sql[0]:
        err('Reference tabReport schema unavailable')
    else:
        chk.execute(schema_sql[0])
        cols={row[1] for row in chk.execute('PRAGMA table_info("tabReport")')}
        try:
            for raw in components['reports']:
                row={k:v for k,v in raw.items() if k in cols}
                keys=list(row)
                sql='INSERT INTO "tabReport"('+','.join('"'+k.replace('"','""')+'"' for k in keys)+') VALUES ('+','.join('?' for _ in keys)+')'
                chk.execute(sql,[row[k] for k in keys])
        except Exception as e:
            err(f'Report metadata violates schema v36 tabReport constraints: {e}')
        else:
            ok(f'Inserted {len(components["reports"])} Report rows against exact schema v36 constraints')
    chk.close(); ref.close()
# Insert Workspace, Workspace Item and Page rows into the exact v36 reference schemas.
ref=sqlite3.connect(str(ref_db)) if ref_db.is_file() else None
if ref is not None:
    ws_chk=sqlite3.connect(':memory:')
    ws_chk.execute('PRAGMA foreign_keys=ON')
    try:
        for table in ['wmn_app_packages','tabWorkspace','tabWorkspaceItem','tabPage']:
            schema_row=ref.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name=?",(table,)).fetchone()
            if not schema_row or not schema_row[0]: raise RuntimeError(f'Missing reference schema for {table}')
            ws_chk.execute(schema_row[0])
        ws_chk.execute("INSERT INTO wmn_app_packages(app_name,app_title,app_version,source_framework,module_json,manifest_json,conversion_status,installed_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)",
                       (app,manifest.get('title'),manifest.get('version'),'WMN','{}',json.dumps(manifest),'READY','2026-09-01','2026-09-01'))
        for table,key in [('tabWorkspace','workspaces'),('tabWorkspaceItem','workspace_items'),('tabPage','pages')]:
            cols={row[1] for row in ws_chk.execute(f'PRAGMA table_info("{table}")')}
            for raw in components[key]:
                row={k:v for k,v in raw.items() if k in cols}; keys=list(row)
                sql=f'INSERT INTO "{table}"('+','.join('\"'+k.replace('\"','\"\"')+'\"' for k in keys)+') VALUES ('+','.join('?' for _ in keys)+')'
                ws_chk.execute(sql,[row[k] for k in keys])
        fk=ws_chk.execute('PRAGMA foreign_key_check').fetchall()
        if fk: err(f'Workspace/Page metadata foreign-key violations: {fk}')
        else: ok(f'Inserted {len(components["workspaces"])} Workspaces / {len(components["workspace_items"])} Workspace Items / {len(components["pages"])} Page against exact schema v36 constraints')
    except Exception as e:
        err(f'Workspace/Page metadata violates schema v36 constraints: {e}')
    finally:
        ws_chk.close(); ref.close()
# hook targets
scripts={s['id']:s for s in components['server_scripts']}
for h in components['hook_bindings']:
    if h.get('source_app')!=app: err(f"Hook owner mismatch: {h.get('id')}")
    if h.get('target_kind')!='SERVER_SCRIPT': err(f"Unsupported hook target kind: {h.get('id')}")
    if h.get('target') not in scripts: err(f"Hook target missing: {h.get('id')}")
    if h.get('reference_doctype') not in doctypes: err(f"Hook DocType missing: {h.get('id')}")
ok(f"Validated {len(components['hook_bindings'])} lifecycle hook bindings")
# managed procedure syntax static traversal
allowed_ops={'let','set','assert','throw','if','for_each','db_get','db_list','db_insert','db_update','db_upsert','db_delete','return','noop'}
special_expr={'get','literal','coalesce','if','eq','ne','gt','gte','lt','lte','close','and','or','not','empty','not_empty','in','add','mul','sub','div','abs','round','min','max','len','sum','concat','trim','lower','upper','matches','uuid','now','today','db_get','db_list','db_exists','db_count','field'}
def walk_steps(steps,path):
    if not isinstance(steps,list): err(f'{path}: steps not list'); return
    for i,s in enumerate(steps):
        p=f'{path}[{i}]'
        if not isinstance(s,dict): err(f'{p}: step not object'); continue
        op=s.get('op')
        if op not in allowed_ops: err(f'{p}: unsupported op {op}')
        # recurse control bodies
        if op=='if':
            walk_steps(s.get('then',[]),p+'.then'); walk_steps(s.get('else',[]),p+'.else')
        if op=='for_each': walk_steps(s.get('steps',[]),p+'.steps')
        # forbid child-local accumulator pattern that previously caused leakage
        if op=='set' and str(s.get('path','')).startswith('vars.'):
            err(f'{p}: vars.* mutation is forbidden in ERP Lite procedures; use doc or per-row postings')
for row in components['server_scripts']:
    sk=row['source_storage_path']; rel=next(x['file'] for x in source_map if x['storage_key']==sk)
    proc=load(APP/rel)
    if proc.get('language')!='wmn-procedure-v1' or proc.get('version')!=1: err(f'Invalid procedure header: {rel}')
    walk_steps(proc.get('steps'),rel)
ok(f"Managed procedure static operation scan complete for {len(components['server_scripts'])} scripts")
# Snapshot safety fields and usage
pos_profile_source=(APP/'sources/scripts/pos_profile_validate.json').read_text(encoding='utf-8')
for required in ['Exactly one POS Profile payment method','Selling Price List','Mode of Payment must belong']:
    if required not in pos_profile_source: err(f'POS Profile validation guard missing: {required}')
ok('POS Profile configuration integrity guard present')

# POS full-retail integrity guards.
pos_validate_source=(APP/'sources/scripts/pos_invoice_validate.json').read_text(encoding='utf-8')
pos_submit_source=(APP/'sources/scripts/pos_invoice_submit.json').read_text(encoding='utf-8')
pos_cancel_source=(APP/'sources/scripts/pos_invoice_cancel.json').read_text(encoding='utf-8')
for required in ['POS Profile Payment','not configured in the POS Profile','not allowed for returns','return_refund_cap']:
    if required not in pos_validate_source: err(f'POS validation guard missing: {required}')
if 'refund_accumulator' not in pos_submit_source: err('POS return submit must accumulate refunded_amount on the original invoice')
if 'stock_item_only' not in pos_submit_source: err('POS submit must isolate stock posting to stock items')
for required in ['POS shift is closed','refund_accumulator_reverse']:
    if required not in pos_cancel_source: err(f'POS cancellation guard missing: {required}')
closing_validate_source=(APP/'sources/scripts/pos_closing_validate.json').read_text(encoding='utf-8')
for required in ['Held POS invoices must be completed or discarded before closing the POS shift.','pos_opening_entry','pos_status']:
    if required not in closing_validate_source: err(f'POS Closing held-invoice guard missing: {required}')
ok('POS Profile payment, refund-cap, held-invoice closing and closed-shift integrity guards present')

snapshot_fields={f['fieldname'] for f in components['doctype_fields'] if f['doctype']=='Stock Posting Snapshot'}
for req in ['previous_qty','previous_valuation_rate','previous_stock_value','expected_after_qty','expected_after_valuation_rate','expected_after_stock_value']:
    if req not in snapshot_fields: err(f'Snapshot safety field missing: {req}')
for name in ['purchase_invoice_cancel','sales_invoice_cancel','pos_invoice_cancel','stock_entry_cancel','stock_reconciliation_cancel']:
    proc=load(APP/f'sources/scripts/{name}.json')
    txt=json.dumps(proc)
    if 'expected_after_qty' not in txt or 'Cancel later stock transactions first' not in txt: err(f'Cancellation post-state guard missing: {name}')
    snapshot_lists=[]
    snapshot_gets=[]
    def collect_snapshot_ops(value):
        if isinstance(value,dict):
            if value.get('op')=='db_list' and value.get('doctype')=='Stock Posting Snapshot': snapshot_lists.append(value)
            if value.get('op')=='db_get' and value.get('doctype')=='Stock Posting Snapshot': snapshot_gets.append(value)
            for child in value.values(): collect_snapshot_ops(child)
        elif isinstance(value,list):
            for child in value: collect_snapshot_ops(child)
    collect_snapshot_ops(proc)
    if len(snapshot_lists)!=1: err(f'Expected one Stock Posting Snapshot db_list in {name}')
    else:
        if set(snapshot_lists[0].get('fields') or []) != {'name'}: err(f'{name}: snapshot enumeration must request name only')
        if snapshot_lists[0].get('as') != 'snapshot_refs': err(f'{name}: snapshot list must bind snapshot_refs')
    if len(snapshot_gets)!=1: err(f'{name}: expected one full Stock Posting Snapshot db_get')
    else:
        if snapshot_gets[0].get('name') != {'get':'snapshot_ref.name'}: err(f'{name}: full snapshot db_get must use snapshot_ref.name')
        if snapshot_gets[0].get('as') != 'snap': err(f'{name}: full snapshot db_get must bind snap')
ok('Stock cancellation post-state guards use full snapshot hydration by record name')
# SQL syntax: synthesize tables and bind all report placeholders to ''.
con=sqlite3.connect(':memory:')
field_by_dt={d:[] for d in doctypes}
for f in components['doctype_fields']: field_by_dt[f['doctype']].append(f['fieldname'])
for d in doctypes:
    cols=['name TEXT','owner TEXT','creation TEXT','modified TEXT','docstatus INTEGER'] + (['parent TEXT','parenttype TEXT','parentfield TEXT','idx INTEGER'] if int(doctypes[d].get('is_child') or 0)==1 else [])
    used={'name','owner','creation','modified','docstatus'} | ({'parent','parenttype','parentfield','idx'} if int(doctypes[d].get('is_child') or 0)==1 else set())
    for f in field_by_dt[d]:
        if f in used: continue
        used.add(f); cols.append('"'+f.replace('"','""')+'"')
    con.execute('CREATE TABLE "tab'+d.replace('"','""')+'" ('+','.join(cols)+')')
placeholder=re.compile(r'%\(([A-Za-z0-9_]+)\)s')
for r in components['reports']:
    rel=next(x['file'] for x in source_map if x['storage_key']==r['query_source_path'])
    sql=(APP/rel).read_text(encoding='utf-8').strip()
    params=[]
    def repl(m): params.append(''); return '?'
    compiled=placeholder.sub(repl,sql)
    try: con.execute(compiled,params).fetchall()
    except Exception as e: err(f"Report SQL invalid {r['report_name']}: {e}")
con.close(); ok(f"Executed syntax validation for {len(components['reports'])} Query Reports")
# print formats required
for dt in ['Sales Invoice','Purchase Invoice','POS Invoice']:
    if not any(p.get('document_type')==dt for p in components['print_formats']): err(f'Print Format missing for {dt}')
ok('Document Print Formats are present')
# package build using standard ZIP outer file
archive={}
for k in COMPONENTS:
    archive[f'metadata/{k}.json']=(json.dumps(components[k],indent=2,ensure_ascii=False)+'\n').encode()
source_index=[]
for row in sorted(source_map,key=lambda x:x['storage_key']):
    payload=(APP/row['file']).read_bytes(); h=hashlib.sha256(payload).hexdigest(); leaf=pathlib.PurePosixPath(row['storage_key']).name
    ap=f'sources/{h}-{leaf}'; archive[ap]=payload
    source_index.append({'storage_key':row['storage_key'],'archive_path':ap,'sha256':h,'size':len(payload)})
archive['metadata/sources.json']=(json.dumps(source_index,indent=2)+'\n').encode(); archive['assets/index.json']=b'[]\n'
targets=profile.get('targets') or ['all']
archive['targets/index.json']=(json.dumps([{'target':t,'application_id':app,'display_name':manifest.get('title',app),'version':manifest['version'],'entry_route':manifest.get('entry_route'),'host_requirements':{}} for t in targets],indent=2)+'\n').encode()
counts={k:len(v) for k,v in components.items()}; counts['managed_sources']=len(source_index); counts['assets']=0
envelope={'package_format':'wmn.application','package_format_version':1,'generated_by':'WMN ERP Lite editable application source','platform_version':'3.24.0+126','schema_version':36,'build_id':str(uuid.uuid4()),'built_at':datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z'),'profile':profile,'manifest':manifest,'component_counts':counts,'warnings':[]}
archive['wmn_app.json']=(json.dumps(envelope,indent=2,ensure_ascii=False)+'\n').encode()
archive['checksums.sha256']=''.join(f'{hashlib.sha256(archive[p]).hexdigest()}  {p}\n' for p in sorted(archive)).encode()
DIST.mkdir(parents=True,exist_ok=True); zip_path=DIST/f'{app}-{manifest["version"]}.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(archive): z.writestr(p,archive[p])
# verify generated zip independent reopen
with zipfile.ZipFile(zip_path) as z:
    names=z.namelist()
    if len(names)!=len(set(names)): err('ZIP duplicate entries')
    if any(n.startswith('/') or '..' in pathlib.PurePosixPath(n).parts or '\\' in n for n in names): err('ZIP unsafe path')
    files={n:z.read(n) for n in names}
    lines=files['checksums.sha256'].decode().splitlines()
    for line in lines:
        h,p=line.split('  ',1)
        if p not in files or hashlib.sha256(files[p]).hexdigest()!=h: err(f'Checksum mismatch: {p}')
    env=json.loads(files['wmn_app.json'])
    if env.get('package_format')!='wmn.application' or env.get('package_format_version')!=1: err('Envelope contract invalid')
    if env.get('schema_version')!=36: err('Envelope schema mismatch')
    if env.get('manifest',{}).get('name')!=app: err('Envelope manifest app mismatch')
    # verify source index hashes
    for row in json.loads(files['metadata/sources.json']):
        payload=files.get(row['archive_path'])
        if payload is None or hashlib.sha256(payload).hexdigest()!=row['sha256']: err(f"Source archive hash mismatch: {row['storage_key']}")
ok(f'Standard ZIP generated and checksum-reopened: {zip_path.name}')
sha=hashlib.sha256(zip_path.read_bytes()).hexdigest(); size=zip_path.stat().st_size
# summary refresh
summary={'app':app,'version':manifest['version'],'platform':'3.24.0+126','schema':36,'zip_size':size,'zip_sha256':sha,'components':counts,'reports':[r['report_name'] for r in components['reports']],'doctypes':[d['name'] for d in components['doctypes']],'scripts':[s['id'] for s in components['server_scripts']]}
(APP/'PACKAGE_SUMMARY.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
report=['# WMN ERP Lite Static Verification','',f'- Application: `{app}`',f'- Version: `{manifest["version"]}`','- Host baseline: `WMN Application Platform 3.24.0+126 / schema v36`',f'- Standard ZIP: `{zip_path.name}`',f'- ZIP bytes: `{size}`',f'- ZIP SHA-256: `{sha}`','',f'## Result: {"PASS" if not errors else "FAIL"}','']
report += [f'- PASS: {c}' for c in checks]
if errors:
    report += ['', '## Errors']+[f'- {e}' for e in errors]
report += ['', '> This is structural/static verification only. Flutter analyzer/tests and real runtime acceptance remain required before treating the baseline as Clean Verified PASS.','']
(APP/'STATIC_VERIFICATION.md').write_text('\n'.join(report),encoding='utf-8')
print(json.dumps({'result':'PASS' if not errors else 'FAIL','errors':errors,'checks':checks,'zip':str(zip_path),'size':size,'sha256':sha,'counts':counts},indent=2,ensure_ascii=False))
sys.exit(1 if errors else 0)
