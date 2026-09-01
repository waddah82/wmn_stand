import '../core/audit/audit_service.dart';
import '../core/database/wmn_database.dart';
import '../core/documents/document_event_bus.dart';
import '../core/documents/document_lifecycle.dart';
import '../core/localization/wmn_localization.dart';
import '../core/numbering/numbering_series_service.dart';
import '../core/settings/settings_repository.dart';
import '../core/settings/theme_controller.dart';
import '../framework/apps/frappe_app_converter.dart';
import '../framework/apps/frappe_app_package_converter.dart';
import '../framework/data_exchange/data_exchange_service.dart';
import '../framework/frappe_compat/frappe_runtime.dart';
import '../framework/meta/meta_service.dart';
import '../framework/model/document_service.dart';
import '../framework/workspaces/workspace_service.dart';
import '../modules/customization/application/customization_service.dart';
import '../modules/reporting/application/frappe_report_service.dart';
import '../modules/reporting/application/report_folder_loader.dart';
import '../modules/reporting/application/query_report_service.dart';
import '../modules/reporting/application/report_builder_service.dart';
import '../modules/reporting/application/script_report_service.dart';
import '../platform/adapters/wmn_platform_adapter_registry.dart';
import '../platform/apps/wmn_application_generator_service.dart';
import '../platform/apps/wmn_application_registry.dart';
import '../platform/capabilities/wmn_capability_registry.dart';
import '../platform/configuration/wmn_configuration_service.dart';
import '../platform/diagnostics/wmn_diagnostics_service.dart';
import '../platform/diagnostics/wmn_log_service.dart';
import '../platform/files/wmn_file_interaction_service.dart';
import '../platform/files/wmn_file_service.dart';
import '../platform/features/wmn_feature_registry.dart';
import '../platform/jobs/wmn_job_service.dart';
import '../platform/notifications/wmn_notification_service.dart';
import '../platform/navigation/wmn_navigation_registry.dart';
import '../platform/pages/wmn_page_controller_registry.dart';
import '../platform/pages/wmn_page_service.dart';
import '../platform/printing/wmn_printing_service.dart';
import '../platform/security/wmn_identity_service.dart';
import '../platform/scripts/wmn_script_runtime.dart';
import '../platform/storage/wmn_storage_service.dart';
import '../platform/security/wmn_permission_service.dart';
import '../platform/kernel/wmn_kernel.dart';
import '../platform/system/wmn_shell_preferences.dart';
import '../platform/system/wmn_system_module_registry.dart';
import '../platform/workflow/wmn_workflow_condition_engine.dart';
import '../platform/workflow/wmn_workflow_runtime.dart';

class WmnRuntime {
  const WmnRuntime({
    required this.database,
    required this.settings,
    required this.locale,
    required this.theme,
    required this.shell,
    required this.kernel,
    required this.systemModules,
    required this.capabilities,
    required this.features,
    required this.identity,
    required this.permissions,
    required this.applications,
    required this.applicationGenerator,
    required this.platformAdapters,
    required this.configuration,
    required this.storage,
    required this.scripts,
    required this.files,
    required this.fileInteractions,
    required this.logs,
    required this.diagnostics,
    required this.jobs,
    required this.notifications,
    required this.printing,
    required this.audit,
    required this.numbering,
    required this.customization,
    required this.meta,
    required this.documents,
    required this.documentLifecycle,
    required this.documentEvents,
    required this.workflow,
    required this.workflowConditions,
    required this.dataExchange,
    required this.reportBuilder,
    required this.queryReports,
    required this.scriptReports,
    required this.frappeReports,
    required this.reportFolders,
    required this.frappeConverter,
    required this.frappePackageConverter,
    required this.workspaces,
    required this.pages,
    required this.pageControllers,
    required this.navigation,
    required this.frappe,
  });

  final WmnDatabase database;
  final SettingsRepository settings;
  final WmnLocaleController locale;
  final WmnThemeController theme;
  final WmnShellPreferences shell;
  final WmnKernel kernel;
  final WmnSystemModuleRegistry systemModules;
  final WmnCapabilityRegistry capabilities;
  final WmnFeatureRegistry features;
  final WmnIdentityService identity;
  final WmnPermissionService permissions;
  final WmnApplicationRegistry applications;
  final WmnApplicationGeneratorService applicationGenerator;
  final WmnPlatformAdapterRegistry platformAdapters;
  final WmnConfigurationService configuration;
  final WmnStorageService storage;
  final WmnScriptRuntime scripts;
  final WmnFileService files;
  final WmnFileInteractionService fileInteractions;
  final WmnLogService logs;
  final WmnDiagnosticsService diagnostics;
  final WmnJobService jobs;
  final WmnNotificationService notifications;
  final WmnPrintingService printing;
  final AuditService audit;
  final NumberingSeriesService numbering;
  final CustomizationService customization;
  final WmnMetaService meta;
  final WmnDocumentService documents;
  final WmnDocumentLifecycleRuntime documentLifecycle;
  final WmnDocumentEventBus documentEvents;
  final WmnWorkflowRuntime workflow;
  final WmnWorkflowConditionRegistry workflowConditions;
  final WmnDataExchangeService dataExchange;
  final ReportBuilderService reportBuilder;
  final WmnQueryReportService queryReports;
  final WmnScriptReportService scriptReports;
  final WmnFrappeReportService frappeReports;
  final WmnReportFolderLoader reportFolders;
  final WmnFrappeAppConverter frappeConverter;
  final WmnFrappeAppPackageConverter frappePackageConverter;
  final WmnWorkspaceService workspaces;
  final WmnPageService pages;
  final WmnPageControllerRegistry pageControllers;
  final WmnNavigationRegistry navigation;
  final WmnFrappeRuntime frappe;
}
