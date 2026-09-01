import '../core/audit/audit_service.dart';
import '../core/database/wmn_database.dart';
import '../core/documents/document_registry.dart';
import '../core/localization/wmn_localization.dart';
import '../core/numbering/numbering_series_service.dart';
import '../core/settings/settings_repository.dart';
import '../core/settings/theme_controller.dart';
import '../framework/apps/frappe_app_converter.dart';
import '../framework/apps/frappe_app_package_converter.dart';
import '../framework/data_exchange/data_exchange_page.dart';
import '../framework/data_exchange/data_exchange_service.dart';
import '../framework/frappe_compat/frappe_runtime.dart';
import '../framework/meta/meta_service.dart';
import '../framework/model/document_service.dart';
import '../framework/workspaces/workspace_service.dart';
import '../modules/customization/application/customization_service.dart';
import '../modules/customization/application/script_engine.dart';
import '../modules/customization/data/customization_repository.dart';
import '../modules/reporting/application/builtin_report_handlers.dart';
import '../modules/reporting/application/frappe_report_service.dart';
import '../modules/reporting/application/report_folder_loader.dart';
import '../modules/reporting/application/query_report_service.dart';
import '../modules/reporting/application/report_builder_service.dart';
import '../modules/reporting/application/script_report_service.dart';
import '../platform/adapters/contracts/wmn_platform_contracts.dart';
import '../platform/adapters/wmn_platform_adapter_registry.dart';
import '../platform/apps/wmn_application_generator_service.dart';
import '../platform/apps/wmn_application_registry.dart';
import '../platform/capabilities/wmn_capability_registry.dart';
import '../platform/configuration/wmn_configuration_service.dart';
import '../platform/diagnostics/wmn_diagnostics_service.dart';
import '../platform/diagnostics/wmn_log_service.dart';
import '../platform/files/wmn_file_adapter.dart';
import '../platform/files/wmn_file_interaction_service.dart';
import '../platform/files/wmn_file_service.dart';
import '../platform/features/wmn_feature_registry.dart';
import '../platform/jobs/wmn_job_service.dart';
import '../platform/notifications/wmn_notification_service.dart';
import '../platform/navigation/wmn_navigation_registry.dart';
import '../platform/pages/wmn_page_controller_registry.dart';
import '../platform/pages/wmn_page_service.dart';
import '../platform/pages/wmn_transaction_workspace_page.dart';
import '../platform/printing/wmn_printing_service.dart';
import '../platform/security/wmn_identity_service.dart';
import '../platform/scripts/wmn_script_runtime.dart';
import '../platform/scripts/wmn_managed_procedure_runtime.dart';
import '../platform/storage/wmn_storage_service.dart';
import '../platform/security/wmn_permission_service.dart';
import '../platform/kernel/wmn_extension_registry.dart';
import '../platform/kernel/wmn_kernel.dart';
import '../platform/system/wmn_shell_preferences.dart';
import '../platform/system/wmn_system_module_registry.dart';
import '../platform/workflow/wmn_workflow_condition_engine.dart';
import 'wmn_app.dart';
import 'wmn_runtime.dart';

class WmnBootstrap {
  static Future<WmnApp> create() async {
    final database = await WmnDatabase.open();
    final settings = SettingsRepository(database);
    final locale = WmnLocaleController(settings);
    final theme = WmnThemeController(settings);
    final shell = WmnShellPreferences(settings);
    final systemModules = WmnSystemModuleRegistry(settings);
    final platformAdapters = WmnPlatformAdapterRegistry();
    await platformAdapters.initialize();
    final runtimeModuleId = platformAdapters.runtimeModuleId;
    if (runtimeModuleId != null && runtimeModuleId != 'server') {
      systemModules.updateEnabled(runtimeModuleId, true);
    }
    final features = WmnFeatureRegistry(database);
    final capabilities = WmnCapabilityRegistry(
      systemModules,
      platformAdapters: platformAdapters,
      features: features,
    );
    final applications = WmnApplicationRegistry(
      database,
      systemModules,
      capabilities,
      platformAdapters: platformAdapters,
    );
    final audit = AuditService(database);
    final configuration = WmnConfigurationService(database: database, audit: audit);
    final storage = WmnStorageService.forDatabase(database);
    final scripts = WmnScriptRuntime(storage: storage);
    final fileDialogService = platformAdapters.tryResolveService('wmn.files.dialog');
    final files = WmnFileService(
      database,
      storage: storage,
      externalReferences: fileDialogService is WmnFileReferenceAdapter
          ? fileDialogService
          : const WmnUnavailableFileReferenceAdapter(),
    );
    final fileInteractions = WmnFileInteractionService(
      files: files,
      adapter: fileDialogService is WmnFileDialogAdapter
          ? fileDialogService
          : const WmnUnavailableFileDialogAdapter(),
    );
    final logs = WmnLogService(database);
    final jobs = WmnJobService(database: database, logs: logs);
    final notifications = WmnNotificationService(database);
    final numbering = NumberingSeriesService(database);

    final documentRegistry = WmnDocumentRegistry(database);
    final customizationRepository = CustomizationRepository(database);
    final meta = WmnMetaService(
      database: database,
      registry: documentRegistry,
      customization: customizationRepository,
    );
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customizationRepository,
      audit: audit,
    );
    final managedProcedures = WmnManagedProcedureRuntime(
      database: database,
      meta: meta,
      documents: documents,
    );
    scripts.registerManagedExecutor(
      WmnManagedProcedureRuntime.language,
      managedProcedures.execute,
    );
    final applicationGenerator = WmnApplicationGeneratorService(
      database: database,
      applications: applications,
      meta: meta,
      storage: storage,
    );
    final printing = WmnPrintingService(
      database,
      files: files,
      documents: documents,
      isFeatureEnabled: features.isFeatureEnabled,
    );
    final identity = WmnIdentityService(database: database, settings: settings);
    final permissions = WmnPermissionService(
      database: database,
      meta: meta,
      identity: identity,
    );
    final workflowConditionRegistry = WmnWorkflowConditionRegistry();
    final workflowConditions = WmnWorkflowConditionEngine(
      registry: workflowConditionRegistry,
    );

    final frappeRuntime = WmnFrappeRuntime.create(
      database: database,
      settings: settings,
      metaService: meta,
      documentService: documents,
      audit: audit,
      identityService: identity,
      permissionService: permissions,
      workflowConditions: workflowConditions,
      isFeatureEnabled: features.isFeatureEnabled,
      scriptRuntime: scripts,
    );
    final scriptEngine = WmnScriptEngine(
      registry: documentRegistry,
      frappeRuntime: frappeRuntime,
    );
    final customization = CustomizationService(
      repository: customizationRepository,
      registry: documentRegistry,
      scriptEngine: scriptEngine,
      audit: audit,
    );

    final dataExchange = WmnDataExchangeService(
      database: database,
      meta: meta,
      documents: documents,
    );

    final workspaces = WmnWorkspaceService(database: database, meta: meta);
    workspaces.ensurePlatformWorkspaces();
    final pages = WmnPageService(
      database: database,
      applications: applications,
      features: features,
    );
    final pageControllers = WmnPageControllerRegistry();
    final scannerService = platformAdapters.tryResolveService('wmn.native.scanner');
    final scanner = scannerService is WmnScannerAdapter ? scannerService : null;
    pageControllers.register(
      'wmn.tool.data_exchange',
      (context, page) => WmnDataExchangePage(
        service: dataExchange,
        meta: meta,
        fileInteractions: fileInteractions,
      ),
    );
    pageControllers.register(
      'wmn.page.transaction_workspace_v1',
      (context, page) => WmnTransactionWorkspacePage(
        page: page,
        frappe: frappeRuntime,
        printing: printing,
        scanner: scanner,
      ),
    );
    final navigation = WmnNavigationRegistry(
      applications: applications,
      workspaces: workspaces,
      pages: pages,
      meta: meta,
      frappe: frappeRuntime,
    );
    documents.addMutationListener((doctype) {
      if (doctype == 'Page') pages.invalidate();
      if (const <String>{
        'Feature',
        'Feature Entitlement',
        'Feature Activation',
      }.contains(doctype)) {
        features.reload();
      }
      if (const <String>{
        'User',
        'Role',
        'Permission',
        'User Role',
        'Role Permission',
        'DocType Permission',
        'User Permission',
        'Document Share',
      }.contains(doctype)) {
        permissions.invalidate();
      }
      if (const <String>{
        'Workflow',
        'Workflow State',
        'Workflow Transition',
      }.contains(doctype)) {
        frappeRuntime.workflowRuntime.invalidate();
      }
    });

    final frappeConverter = WmnFrappeAppConverter(database: database, meta: meta);
    final frappePackageConverter = WmnFrappeAppPackageConverter(
      database: database,
      meta: meta,
      converter: frappeConverter,
      workspaces: workspaces,
      pages: pages,
      storage: storage,
    );
    final reportBuilder = ReportBuilderService(
      database: database,
      customization: customizationRepository,
      meta: meta,
    );
    final queryReports = WmnQueryReportService(database: database);
    final scriptReports = WmnScriptReportService(
      database: database,
      storage: storage,
      scriptRuntime: scripts,
    );
    WmnBuiltinReportHandlers.register(
      database: database,
      scriptReports: scriptReports,
    );
    final frappeReports = WmnFrappeReportService(
      database: database,
      reportBuilder: reportBuilder,
      queryReports: queryReports,
      scriptReports: scriptReports,
      storage: storage,
      isFeatureEnabled: features.isFeatureEnabled,
      canReportOnDocType: (doctype) =>
          permissions.hasPermission(doctype, 'read') &&
          permissions.hasPermission(doctype, 'report'),
    );
    frappeReports.normalizeSources();
    final reportFolders = WmnReportFolderLoader(
      reports: frappeReports,
      storage: storage,
    );
    documents.addMutationListener((doctype) {
      if (doctype == 'Report') frappeReports.normalizeSources();
    });

    final kernel = WmnKernel(
      modules: systemModules,
      capabilities: capabilities,
      applications: applications,
    );
    final diagnostics = WmnDiagnosticsService(database: database, kernel: kernel, logs: logs);
    jobs.registerHandler(
      'wmn.system.capture_diagnostics',
      (_) => <String, Object?>{'log_id': diagnostics.recordSnapshot()},
    );
    kernel.extensions
      ..define(const WmnExtensionPoint(id: 'platform.startup', description: 'Native platform startup extensions.'))
      ..define(const WmnExtensionPoint(id: 'platform.adapters', description: 'Native host/platform adapter contributions.'))
      ..define(const WmnExtensionPoint(id: 'shell.navigation', description: 'Application navigation contributions.'))
      ..define(const WmnExtensionPoint(id: 'documents.events', description: 'Transactional document lifecycle event contributions.'))
      ..define(const WmnExtensionPoint(id: 'workflows.conditions', description: 'Compiled workflow condition handlers.'))
      ..define(const WmnExtensionPoint(id: 'pages.controllers', description: 'Compiled custom WMN Page controller contributions.'))
      ..define(const WmnExtensionPoint(id: 'reports.sources', description: 'Application report-source contributions.'))
      ..define(const WmnExtensionPoint(id: 'printing.adapters', description: 'Platform printing adapter contributions.'))
      ..define(const WmnExtensionPoint(id: 'storage.adapters', description: 'Platform content-storage adapter contributions.'))
      ..define(const WmnExtensionPoint(id: 'notifications.adapters', description: 'Email, SMS and push delivery adapters.'))
      ..define(const WmnExtensionPoint(id: 'jobs.runners', description: 'Platform background-job runner adapters.'));
    kernel.services
      ..register('wmn.database', database)
      ..register('wmn.settings', settings)
      ..register('wmn.system_modules', systemModules)
      ..register('wmn.capabilities', capabilities)
      ..register('wmn.features', features)
      ..register('wmn.identity', identity)
      ..register('wmn.permissions', permissions)
      ..register('wmn.applications', applications)
      ..register('wmn.application_generator', applicationGenerator)
      ..register('wmn.platform_adapters', platformAdapters)
      ..register('wmn.configuration', configuration)
      ..register('wmn.storage', storage)
      ..register('wmn.scripts', scripts)
      ..register('wmn.files', files)
      ..register('wmn.file_interactions', fileInteractions)
      ..register('wmn.data_exchange', dataExchange)
      ..register('wmn.logs', logs)
      ..register('wmn.diagnostics', diagnostics)
      ..register('wmn.jobs', jobs)
      ..register('wmn.notifications', notifications)
      ..register('wmn.printing', printing)
      ..register('wmn.meta', meta)
      ..register('wmn.documents', frappeRuntime.documents)
      ..register('wmn.document_lifecycle', frappeRuntime.lifecycle)
      ..register('wmn.document_events', frappeRuntime.lifecycle.events)
      ..register('wmn.workflow', frappeRuntime.workflowRuntime)
      ..register('wmn.workflow_conditions', workflowConditionRegistry)
      ..register('wmn.workflow_condition_engine', workflowConditions)
      ..register('wmn.audit', audit)
      ..register('wmn.workspaces', workspaces)
      ..register('wmn.pages', pages)
      ..register('wmn.page_controllers', pageControllers)
      ..register('wmn.navigation', navigation)
      ..register('wmn.report_builder', reportBuilder)
      ..register('wmn.query_reports', queryReports)
      ..register('wmn.script_reports', scriptReports)
      ..register('wmn.reports', frappeReports)
      ..register('wmn.report_folders', reportFolders);
    for (final serviceId in platformAdapters.serviceIds) {
      final service = platformAdapters.tryResolveService(serviceId);
      if (service != null) {
        kernel.services.register(serviceId, service);
      }
    }
    kernel.start();

    return WmnApp(
      runtime: WmnRuntime(
        database: database,
        settings: settings,
        locale: locale,
        theme: theme,
        shell: shell,
        kernel: kernel,
        systemModules: systemModules,
        capabilities: capabilities,
        features: features,
        identity: identity,
        permissions: permissions,
        applications: applications,
        applicationGenerator: applicationGenerator,
        platformAdapters: platformAdapters,
        configuration: configuration,
        storage: storage,
        scripts: scripts,
        files: files,
        fileInteractions: fileInteractions,
        logs: logs,
        diagnostics: diagnostics,
        jobs: jobs,
        notifications: notifications,
        printing: printing,
        audit: audit,
        numbering: numbering,
        customization: customization,
        meta: meta,
        documents: documents,
        documentLifecycle: frappeRuntime.lifecycle,
        documentEvents: frappeRuntime.lifecycle.events,
        workflow: frappeRuntime.workflowRuntime,
        workflowConditions: workflowConditionRegistry,
        dataExchange: dataExchange,
        reportBuilder: reportBuilder,
        queryReports: queryReports,
        scriptReports: scriptReports,
        frappeReports: frappeReports,
        reportFolders: reportFolders,
        frappeConverter: frappeConverter,
        frappePackageConverter: frappePackageConverter,
        workspaces: workspaces,
        pages: pages,
        pageControllers: pageControllers,
        navigation: navigation,
        frappe: frappeRuntime,
      ),
    );
  }
}
