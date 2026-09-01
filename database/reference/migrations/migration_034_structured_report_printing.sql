UPDATE print_formats
SET template_text='<h1>{{ report.title }}</h1>
{{ report.filters_block }}
{{ report.table }}',
    metadata_json=json_set(
      COALESCE(NULLIF(metadata_json,''),'{}'),
      '$.protected',1,
      '$.general_report',1,
      '$.structured_report',1,
      '$.auto_landscape',1,
      '$.repeat_table_header',1
    ),
    updated_at=datetime('now')
WHERE code='WMN-GENERAL-REPORT'
  AND target_type='GENERAL_REPORT'
  AND json_extract(metadata_json,'$.protected')=1;
