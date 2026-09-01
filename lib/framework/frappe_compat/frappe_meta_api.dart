import '../meta/doctype_meta.dart';
import '../meta/meta_service.dart';

class WmnFrappeMetaApi {
  const WmnFrappeMetaApi(this.meta);

  final WmnMetaService meta;

  Map<String, Object?>? getMeta(String doctype) {
    final dt = meta.doctype(doctype);
    if (dt == null) return null;
    return <String, Object?>{
      'name': dt.name,
      'module': dt.module,
      'title_field': dt.titleField,
      'autoname': dt.autoname,
      'issingle': dt.isSingle ? 1 : 0,
      'istable': dt.isChild ? 1 : 0,
      'is_submittable': dt.isSubmittable ? 1 : 0,
      'track_changes': dt.trackChanges ? 1 : 0,
      'fields': dt.fields.map(_fieldJson).toList(growable: false),
      'metadata': dt.metadata,
    };
  }

  Map<String, Object?>? getDocField(String doctype, String fieldname) {
    final field = meta.doctype(doctype)?.field(fieldname);
    return field == null ? null : _fieldJson(field);
  }

  bool hasField(String doctype, String fieldname) => meta.doctype(doctype)?.field(fieldname) != null;

  int getPrecision(String doctype, String fieldname, {int fallback = 2}) {
    return meta.doctype(doctype)?.field(fieldname)?.precision ?? fallback;
  }

  String titleField(String doctype) => meta.doctype(doctype)?.titleField ?? 'name';

  List<String> tableFields(String doctype) => meta
      .doctype(doctype)
      ?.fields
      .where((field) => const {'Table', 'Table MultiSelect'}.contains(field.fieldType))
      .map((field) => field.fieldName)
      .toList(growable: false) ??
      const [];

  Map<String, Object?> _fieldJson(WmnFieldMeta field) => <String, Object?>{
        'fieldname': field.fieldName,
        'label': field.label,
        'fieldtype': field.fieldType,
        'options': field.options,
        'idx': field.index,
        'reqd': field.required ? 1 : 0,
        'read_only': field.readOnly ? 1 : 0,
        'hidden': field.hidden ? 1 : 0,
        'in_list_view': field.inListView ? 1 : 0,
        'in_standard_filter': field.inStandardFilter ? 1 : 0,
        'searchable': field.searchable ? 1 : 0,
        'allow_on_submit': field.allowOnSubmit ? 1 : 0,
        'default': field.defaultValue,
        'depends_on': field.dependsOn,
        'mandatory_depends_on': field.mandatoryDependsOn,
        'read_only_depends_on': field.readOnlyDependsOn,
        'fetch_from': field.fetchFrom,
        'precision': field.precision,
        'length': field.length,
        'is_custom_field': field.isCustom ? 1 : 0,
        ...field.metadata,
      };
}
