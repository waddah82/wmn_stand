#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'applications' / 'wmn_pos_extensions'
META = APP / 'metadata'
DIST = APP / 'dist' / 'wmn_pos_extensions-1.0.0.zip'

COMPONENTS = [
    'modules','doctypes','doctype_fields','doctype_permissions','list_views',
    'custom_fields','property_overrides','numbering_series','roles','permissions',
    'role_permissions','workspaces','workspace_items','pages','reports',
    'report_filters','report_columns','print_formats','client_scripts',
    'server_scripts','workflows','workflow_states','workflow_transitions',
    'method_bindings','hook_bindings','number_cards','dashboard_charts',
]

OPS = {
    'let','set','map_put','append','assert','throw','if','for_each','db_get','db_list',
    'db_insert','db_update','db_upsert','db_delete','return','noop',
}
EXPRS = {
    'get','literal','coalesce','if','eq','ne','gt','gte','lt','lte','close','and','or','not',
    'empty','not_empty','in','add','mul','sub','div','abs','round','min','max','len','sum',
    'concat','slice','starts_with','ends_with','to_number','floor','trim','lower','upper',
    'matches','uuid','now','today','db_get','db_list','db_exists','db_count','field',
}
EXPR_NON_KEYS = {
    'test','then','else','value','precision','items','as','start','length','from','name',
    'doctype','filters','fields','limit','offset','order_by','fieldname','key',
}

errors: list[str] = []
info: list[str] = []

def fail(msg: str) -> None:
    errors.append(msg)

def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except Exception as exc:
        fail(f'Invalid JSON {path.relative_to(ROOT)}: {exc}')
        return None

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

if not APP.exists():
    fail('applications/wmn_pos_extensions is missing.')

manifest = read_json(APP/'manifest.json') or {}
profile = read_json(APP/'profile.json') or {}
components: dict[str, list[dict]] = {}
for name in COMPONENTS:
    p = META/f'{name}.json'
    if not p.exists():
        fail(f'Missing metadata component: metadata/{name}.json')
        components[name] = []
        continue
    value = read_json(p)
    if not isinstance(value, list):
        fail(f'metadata/{name}.json must be a JSON array.')
        value = []
    components[name] = [x for x in value if isinstance(x, dict)]
    if len(components[name]) != len(value):
        fail(f'metadata/{name}.json contains non-object rows.')

if manifest.get('name') != 'wmn_pos_extensions': fail('manifest.name must be wmn_pos_extensions.')
if manifest.get('version') != '1.0.0': fail('manifest.version must be 1.0.0.')
if manifest.get('minimum_platform_version') != '3.25.0': fail('minimum_platform_version must be 3.25.0.')
if 'wmn_erp_lite' not in (manifest.get('required_applications') or []): fail('wmn_erp_lite must be a required application.')
if '.wmnapp' in json.dumps(manifest).lower(): fail('Legacy .wmnapp terminology is forbidden in the application manifest.')

owned = {d.get('name') for d in components['doctypes'] if d.get('name')}
child = {d.get('name') for d in components['doctypes'] if d.get('is_child') == 1}
if len(owned) != 10: fail(f'Expected 10 owned DocTypes, found {len(owned)}.')
if len(components['doctype_fields']) != 87: fail(f'Expected 87 DocType fields, found {len(components["doctype_fields"])}.')
if len(components['server_scripts']) != 9: fail(f'Expected 9 managed scripts, found {len(components["server_scripts"])}.')
if len(components['reports']) != 3: fail(f'Expected 3 reports, found {len(components["reports"])}.')
if len(components['workspaces']) != 1 or len(components['pages']) != 1: fail('Expected one workspace and one POS page.')

# Reports must use the exact generic tabReport contract. Do not accept legacy
# aliases here: the installer persists these rows directly into the platform
# schema, where report_name and ref_doctype are required canonical fields.
for report in components['reports']:
    report_id = str(report.get('name') or '').strip()
    if not report_id:
        fail(f'Report is missing name: {report}')
    if not str(report.get('report_name') or '').strip():
        fail(f'Report {report_id or "<unnamed>"} is missing report_name.')
    if not str(report.get('ref_doctype') or '').strip():
        fail(f'Report {report_id or "<unnamed>"} is missing ref_doctype.')
    if report.get('report_type') != 'Query Report':
        fail(f'Report {report_id or "<unnamed>"} must use report_type "Query Report".')
    if report.get('script_source_type') not in {'NATIVE_HANDLER', 'STORAGE_FILE'}:
        fail(
            f'Report {report_id or "<unnamed>"} must use a schema-supported '
            'script_source_type (NATIVE_HANDLER or STORAGE_FILE).'
        )
    if 'reference_doctype' in report:
        fail(f'Report {report_id or "<unnamed>"} uses unsupported reference_doctype alias.')

report_names = {str(report.get('name') or '').strip() for report in components['reports']}
report_column_schema = {
    'name', 'parent', 'parentfield', 'parenttype', 'idx', 'fieldname', 'label',
    'label_ar', 'fieldtype', 'options', 'width', 'precision', 'alignment',
    'aggregate', 'hidden', 'created_at', 'updated_at',
}
for column in components['report_columns']:
    column_id = str(column.get('name') or '').strip() or '<unnamed>'
    unknown = sorted(set(column) - report_column_schema)
    if unknown:
        fail(f'Report Column {column_id} uses non-schema fields: {", ".join(unknown)}.')
    for required in {
        'name', 'parent', 'parentfield', 'parenttype', 'fieldname', 'label',
        'fieldtype', 'created_at', 'updated_at',
    }:
        if not str(column.get(required) or '').strip():
            fail(f'Report Column {column_id} is missing {required}.')
    if column.get('parent') not in report_names:
        fail(f'Report Column {column_id} references an unknown report parent.')
    if column.get('parentfield') != 'columns' or column.get('parenttype') != 'Report':
        fail(f'Report Column {column_id} must use Report.columns parent metadata.')

# Metadata field integrity.
field_keys = set()
for f in components['doctype_fields']:
    dt = str(f.get('doctype') or '')
    fn = str(f.get('fieldname') or '')
    key = (dt, fn)
    if not dt or not fn: fail(f'DocType field missing doctype/fieldname: {f}')
    if key in field_keys: fail(f'Duplicate DocType field: {dt}.{fn}')
    field_keys.add(key)
    if dt not in owned: fail(f'Owned field points to non-owned DocType: {dt}.{fn}')
    if f.get('hidden') == 1 and f.get('reqd') == 1 and f.get('default_json') in (None, '', 'null'):
        fail(f'{dt}.{fn} cannot be hidden and mandatory without a default.')
    if f.get('fieldtype') == 'Table':
        target = str(f.get('options') or '')
        if target not in child: fail(f'{dt}.{fn} Table target must be an owned child DocType: {target}')

# Link options may target dependency/system DocTypes. Enforce known set to catch typos.
erp_lite = read_json(ROOT/'applications'/'wmn_erp_lite'/'metadata'/'doctypes.json') or []
erp_names = {d.get('name') for d in erp_lite if isinstance(d, dict)}
system_links = {'User','DocType','Report','Page','Workspace','Print Format'}
known = owned | erp_names | system_links
for f in components['doctype_fields']:
    if f.get('fieldtype') in {'Link','Dynamic Link'} and f.get('fieldtype') == 'Link':
        target = str(f.get('options') or '').strip()
        if target and target not in known:
            fail(f'Unknown Link target {target} at {f.get("doctype")}.{f.get("fieldname")}')

contrib = set(manifest.get('metadata_contributions') or [])
for cf in components['custom_fields']:
    dt = str(cf.get('document_type') or '')
    if dt not in contrib: fail(f'Custom field target {dt} is not declared in metadata_contributions.')
    if dt not in erp_names and dt not in system_links: fail(f'Custom field target is not supplied by required application/system: {dt}')

# Page contract must remain generic and app-owned.
page = components['pages'][0] if components['pages'] else {}
if page.get('controller_key') != 'wmn.page.transaction_workspace_v1': fail('POS page must use generic transaction workspace controller.')
try:
    page_meta = json.loads(page.get('metadata_json') or '{}')
except Exception as exc:
    page_meta = {}; fail(f'Invalid page metadata_json: {exc}')
for key, expected in {
    'transaction_doctype':'POS Invoice','profile_doctype':'POS Profile','product_doctype':'Item',
    'party_doctype':'Customer','barcode_resolver_method':'wmn_pos_extensions.resolve_barcode',
    'pricing_resolver_method':'wmn_pos_extensions.resolve_pricing',
}.items():
    if page_meta.get(key) != expected: fail(f'POS page metadata {key} must be {expected!r}.')
if not page_meta.get('pricing_code_enabled'): fail('POS page must enable application pricing-code resolver.')

# Methods/scripts/hooks/source mapping.
method_names = {m.get('method_name') for m in components['method_bindings']}
for expected in {'wmn_pos_extensions.resolve_barcode','wmn_pos_extensions.resolve_pricing'}:
    if expected not in method_names: fail(f'Missing managed API method binding: {expected}')
script_by_name = {s.get('name'): s for s in components['server_scripts']}
hooks = components['hook_bindings']
for h in hooks:
    if h.get('source_app') != 'wmn_pos_extensions': fail(f'Hook owned by wrong app: {h.get("id")}')
    target = h.get('target')
    if target not in script_by_name: fail(f'Hook target is not a registered Server Script: {target}')

index = read_json(APP/'sources'/'index.json') or []
if not isinstance(index, list): index=[]; fail('sources/index.json must be an array.')
source_by_key = {}
for row in index:
    if not isinstance(row, dict): fail('sources/index.json contains non-object row.'); continue
    key = str(row.get('storage_key') or '').strip(); rel = str(row.get('file') or '').strip()
    if not key or not rel: fail(f'Invalid source index row: {row}'); continue
    if key in source_by_key: fail(f'Duplicate source storage key: {key}')
    source_by_key[key]=rel
    p=APP/rel
    if not p.exists(): fail(f'Missing managed source file: {rel}')
if len(source_by_key) != 12: fail(f'Expected 12 managed sources, found {len(source_by_key)}.')

for s in components['server_scripts']:
    path = str(s.get('source_storage_path') or '')
    if path not in source_by_key: fail(f'Server Script source is missing from source index: {path}')
for r in components['reports']:
    if r.get('query_source_type') != 'STORAGE_FILE': fail(f'Report {r.get("name")} must use STORAGE_FILE.')
    path = str(r.get('query_source_path') or '')
    if path not in source_by_key: fail(f'Report source is missing from source index: {path}')

# Managed procedure vocabulary + no executable Frappe runtime source.
def scan_expr(value, where):
    if isinstance(value, list):
        for x in value: scan_expr(x, where)
    elif isinstance(value, dict):
        # Expressions with arbitrary object literals are valid. Only flag an unknown single operator-looking key.
        keys=set(value)
        recognized=keys & EXPRS
        if len(keys)==1 and not recognized and next(iter(keys)) not in EXPR_NON_KEYS:
            key=next(iter(keys))
            # object-literal keys are expected in values; do not flag common state/result maps
            if key not in {'resolved','matched','offset','result','sum_length','total','rate','barcode','rule_name','message','discount_amount','pricing_type','quantity','product_code','unit','weighted','raw','used'}:
                fail(f'Unknown managed expression/operator key {key!r} in {where}.')
        for v in value.values(): scan_expr(v, where)

def scan_steps(steps, where):
    if not isinstance(steps, list): fail(f'Procedure steps must be an array in {where}.'); return
    for step in steps:
        if not isinstance(step, dict): fail(f'Non-object procedure step in {where}.'); continue
        op=step.get('op')
        if op not in OPS: fail(f'Unsupported managed procedure op {op!r} in {where}.')
        for k,v in step.items():
            if k in {'steps','then','else'} and isinstance(v,list): scan_steps(v,where)
            else: scan_expr(v,where)

for s in components['server_scripts']:
    sp=APP/source_by_key.get(str(s.get('source_storage_path') or ''),'__missing__')
    if sp.exists():
        proc=read_json(sp)
        if not isinstance(proc,dict): continue
        if proc.get('language')!='wmn-procedure-v1' or proc.get('version')!=1:
            fail(f'{sp.relative_to(APP)} must be wmn-procedure-v1 version 1.')
        scan_steps(proc.get('steps'),str(sp.relative_to(APP)))

# Generic platform boundary: only generic resolver/primitives in Flutter, no app/domain names.
workspace_source=(ROOT/'lib/platform/pages/wmn_transaction_workspace_page.dart').read_text(encoding='utf-8')
procedure_source=(ROOT/'lib/platform/scripts/wmn_managed_procedure_runtime.dart').read_text(encoding='utf-8')
combined=workspace_source+'\n'+procedure_source
for term in ['wmn_pos_extensions','Barcode Structure','WMN POS Promotion','WMN POS Coupon','WMN POS Cash Movement']:
    if term in combined: fail(f'Application-specific term leaked into generic Flutter Runtime: {term}')
for token in ['barcode_resolver_method','pricing_resolver_method']:
    if token not in workspace_source: fail(f'Generic transaction workspace is missing resolver contract: {token}')
for token in ["case 'map_put'", "case 'append'", "map.containsKey('slice')", "map.containsKey('starts_with')", "map.containsKey('ends_with')", "map.containsKey('to_number')", "map.containsKey('floor')"]:
    if token not in procedure_source: fail(f'Generic managed-procedure primitive missing: {token}')
if '.wmnapp' in procedure_source: fail('Legacy .wmnapp terminology remains in managed procedure runtime.')

# Report SQL syntax against generated extension tables.
conn=sqlite3.connect(':memory:')
fields_by_dt={dt:[] for dt in owned}
for f in components['doctype_fields']:
    fields_by_dt.setdefault(f.get('doctype'),[]).append(f.get('fieldname'))
for dt in owned:
    cols=['name','docstatus','owner','creation','modified','modified_by','idx','parent','parentfield','parenttype']
    cols += [str(x) for x in fields_by_dt.get(dt,[]) if x and x not in cols]
    quoted=', '.join(f'"{c}" NUMERIC' for c in cols)
    conn.execute(f'CREATE TABLE "tab{dt}" ({quoted})')
for r in components['reports']:
    path=APP/source_by_key.get(str(r.get('query_source_path') or ''),'__missing__')
    if path.exists():
        sql=path.read_text(encoding='utf-8').strip().rstrip(';')
        try: conn.execute('EXPLAIN QUERY PLAN '+sql)
        except Exception as exc: fail(f'Report SQL invalid for {r.get("name")}: {exc}')
conn.close()

# Print format contract.
formats=components['print_formats']
if len(formats)!=1: fail(f'Expected one extension Print Format, found {len(formats)}.')
elif formats[0].get('renderer_id')!='escpos' or formats[0].get('document_type')!='POS Invoice':
    fail('Extension thermal receipt must target POS Invoice with escpos renderer.')
elif float(formats[0].get('paper_width_mm') or 0) <= 0 or float(formats[0].get('paper_height_mm') or 0) <= 0:
    fail('Extension thermal receipt paper dimensions must satisfy the print_formats positive-size constraints.')

# Standard ZIP contract/checksums.
if not DIST.exists():
    fail('Runtime install ZIP is missing; build applications/wmn_pos_extensions/dist/wmn_pos_extensions-1.0.0.zip.')
else:
    try:
        with zipfile.ZipFile(DIST) as z:
            names=z.namelist()
            if any(n.startswith('/') or '..' in Path(n).parts or '\\' in n for n in names): fail('ZIP contains unsafe archive paths.')
            for req in ['wmn_app.json','checksums.sha256','metadata/sources.json','metadata/pages.json','metadata/doctypes.json']:
                if req not in names: fail(f'ZIP missing required file: {req}')
            envelope=json.loads(z.read('wmn_app.json'))
            if envelope.get('package_format')!='wmn.application' or envelope.get('package_format_version')!=1: fail('Invalid standard WMN package envelope.')
            if envelope.get('platform_version')!='3.25.0+127': fail('ZIP platform_version must be 3.25.0+127.')
            if envelope.get('schema_version')!=36: fail('ZIP schema_version must remain 36.')
            if (envelope.get('manifest') or {}).get('name')!='wmn_pos_extensions': fail('ZIP manifest mismatch.')
            packaged_columns=json.loads(z.read('metadata/report_columns.json'))
            if packaged_columns != components['report_columns']:
                fail('ZIP report_columns metadata is stale relative to the application source.')
            packaged_formats=json.loads(z.read('metadata/print_formats.json'))
            if packaged_formats != components['print_formats']:
                fail('ZIP print_formats metadata is stale relative to the application source.')
            packaged_sources=json.loads(z.read('metadata/sources.json'))
            packaged_source_by_key={str(row.get('storage_key') or ''):row for row in packaged_sources}
            for storage_key, relative_path in source_by_key.items():
                packaged_source=packaged_source_by_key.get(storage_key, {})
                source_bytes=(APP/relative_path).read_bytes()
                archive_path=str(packaged_source.get('archive_path') or '')
                if packaged_source.get('sha256') != sha256(source_bytes):
                    fail(f'ZIP managed source hash is stale: {storage_key}')
                elif packaged_source.get('size') != len(source_bytes):
                    fail(f'ZIP managed source size is stale: {storage_key}')
                elif archive_path not in names or z.read(archive_path) != source_bytes:
                    fail(f'ZIP managed source payload is stale: {storage_key}')
            packaged_reports=json.loads(z.read('metadata/reports.json'))
            packaged_report_by_name={str(row.get('name') or ''):row for row in packaged_reports}
            for source_report in components['reports']:
                packaged_report=packaged_report_by_name.get(str(source_report.get('name') or ''), {})
                for field in {'report_name','ref_doctype','report_type','script_source_type'}:
                    if packaged_report.get(field) != source_report.get(field):
                        fail(f'ZIP report {source_report.get("name")} has stale {field}.')
            checks=z.read('checksums.sha256').decode('utf-8').splitlines()
            for line in checks:
                if not line.strip(): continue
                m=re.fullmatch(r'([0-9a-f]{64})  (.+)',line)
                if not m: fail(f'Malformed checksum line: {line}'); continue
                expected,name=m.groups()
                if name not in names: fail(f'Checksum references missing ZIP entry: {name}')
                elif sha256(z.read(name))!=expected: fail(f'Checksum mismatch for ZIP entry: {name}')
            if any(n.lower().endswith('.wmnapp') for n in names): fail('ZIP must not contain .wmnapp files.')
            if any(n.lower().endswith(('.py','.js','.ts')) for n in names): fail('Portable runtime ZIP must not execute/carry Frappe Python/JS runtime source.')
    except Exception as exc:
        fail(f'Cannot validate standard ZIP: {exc}')

# Explicit scope policy: unsupported original integrations must be documented, not silently claimed.
portmap=(APP/'SOURCE_PORT_MAP.md').read_text(encoding='utf-8') if (APP/'SOURCE_PORT_MAP.md').exists() else ''
for phrase in ['Payment gateway','Offline','Supervisor','handoff']:
    if phrase.lower() not in portmap.lower(): fail(f'SOURCE_PORT_MAP must explicitly state status for original feature: {phrase}')

counts={name:len(rows) for name,rows in components.items()}
info += [
    f"DocTypes={counts['doctypes']}", f"Fields={counts['doctype_fields']}",
    f"ManagedScripts={counts['server_scripts']}", f"ManagedSources={len(source_by_key)}",
    f"Reports={counts['reports']}", f"WorkspaceItems={counts['workspace_items']}",
    f"Methods={counts['method_bindings']}", f"Hooks={counts['hook_bindings']}",
]

if errors:
    print('WMN POS EXTENSIONS VERIFICATION: FAIL')
    for e in errors: print(' -',e)
    sys.exit(1)
print('WMN POS EXTENSIONS VERIFICATION: PASS')
for x in info: print(' -',x)
print(' - generic platform boundary: PASS')
print(' - standard ZIP + SHA-256 contract: PASS')
print(' - report SQL syntax: PASS')
