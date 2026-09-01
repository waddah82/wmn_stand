enum WmnSystemDocTypeKind {
  configuration,
  runtimeEntity,
  log,
  developerMetadata,
}

class WmnSystemDocTypeRuntimeBinding {
  const WmnSystemDocTypeRuntimeBinding({
    required this.doctype,
    required this.kind,
    required this.ownerServiceId,
    this.genericEditingAllowed = false,
  });

  final String doctype;
  final WmnSystemDocTypeKind kind;
  final String ownerServiceId;
  final bool genericEditingAllowed;
}

/// Explicit ownership map for every System DocType.
///
/// A System DocType is metadata/configuration around a runtime capability; it
/// is not itself the capability. Keeping this map exhaustive prevents a
/// metadata-only facade from being mistaken for a finished runtime engine.
class WmnSystemDocTypeRuntimeCatalog {
  const WmnSystemDocTypeRuntimeCatalog._();

  static const List<WmnSystemDocTypeRuntimeBinding> bindings = <WmnSystemDocTypeRuntimeBinding>[
    WmnSystemDocTypeRuntimeBinding(doctype: 'Application', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.applications'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Application Build Profile', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.application_generator', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Application Build', kind: WmnSystemDocTypeKind.log, ownerServiceId: 'wmn.application_generator'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Audit Log', kind: WmnSystemDocTypeKind.log, ownerServiceId: 'wmn.audit'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Background Job', kind: WmnSystemDocTypeKind.log, ownerServiceId: 'wmn.jobs'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'DocType', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.meta'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'DocType Permission', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.permissions', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Document Share', kind: WmnSystemDocTypeKind.runtimeEntity, ownerServiceId: 'wmn.permissions', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Feature', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.features'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Feature Activation', kind: WmnSystemDocTypeKind.runtimeEntity, ownerServiceId: 'wmn.features'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Feature Entitlement', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.features'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'File', kind: WmnSystemDocTypeKind.runtimeEntity, ownerServiceId: 'wmn.files'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'File Settings', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.files', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Module', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.meta'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Notification', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.notifications', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Page', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.pages', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Permission', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.permissions', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Print Format', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.printing', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Letter Head', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.printing', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Print Job', kind: WmnSystemDocTypeKind.log, ownerServiceId: 'wmn.printing'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Print Settings', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.printing', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Printer', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.printing', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Report', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.reports', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Report Column', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.reports', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Report Filter', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.reports', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Role', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.permissions', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Role Permission', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.permissions', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Scheduled Job', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.jobs', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'System Log', kind: WmnSystemDocTypeKind.log, ownerServiceId: 'wmn.logs'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'System Setting', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.configuration'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'User', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.identity', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'User Permission', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.permissions', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'User Role', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.permissions', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Workflow', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.workflow', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Workflow Action', kind: WmnSystemDocTypeKind.runtimeEntity, ownerServiceId: 'wmn.workflow'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Workflow State', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.workflow', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Workflow Transition', kind: WmnSystemDocTypeKind.configuration, ownerServiceId: 'wmn.workflow', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Workspace', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.workspaces', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Workspace Item', kind: WmnSystemDocTypeKind.developerMetadata, ownerServiceId: 'wmn.workspaces', genericEditingAllowed: true),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Data Import Job', kind: WmnSystemDocTypeKind.log, ownerServiceId: 'wmn.data_exchange'),
    WmnSystemDocTypeRuntimeBinding(doctype: 'Data Export Job', kind: WmnSystemDocTypeKind.log, ownerServiceId: 'wmn.data_exchange'),
  ];

  static WmnSystemDocTypeRuntimeBinding? binding(String doctype) {
    for (final entry in bindings) {
      if (entry.doctype == doctype) return entry;
    }
    return null;
  }
}
