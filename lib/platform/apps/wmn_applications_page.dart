import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import '../files/wmn_file_adapter.dart';
import '../files/wmn_file_interaction_service.dart';
import 'wmn_app_manifest.dart';
import 'wmn_application_generator_service.dart';
import 'wmn_application_registry.dart';

class WmnApplicationsPage extends StatefulWidget {
  const WmnApplicationsPage({
    super.key,
    required this.registry,
    required this.generator,
    required this.fileInteractions,
  });

  final WmnApplicationRegistry registry;
  final WmnApplicationGeneratorService generator;
  final WmnFileInteractionService fileInteractions;

  @override
  State<WmnApplicationsPage> createState() => _WmnApplicationsPageState();
}

class _WmnApplicationsPageState extends State<WmnApplicationsPage> {
  WmnApplicationRegistry get registry => widget.registry;
  WmnApplicationGeneratorService get generator => widget.generator;
  WmnFileInteractionService get files => widget.fileInteractions;

  static const _packageFilter = WmnFileTypeFilter(
    label: 'WMN Application Package',
    extensions: <String>['zip'],
    mimeTypes: <String>['application/zip', 'application/octet-stream'],
    webWildCards: <String>['.zip'],
  );

  @override
  Widget build(BuildContext context) {
    final apps = registry.applications();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.wmnT('applications'),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.wmnT('applications_help'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: files.canPick ? _importPackage : null,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(context.wmnT('import_application_package')),
                ),
                FilledButton.icon(
                  onPressed: _createApplication,
                  icon: const Icon(Icons.add),
                  label: Text(context.wmnT('new_application')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (apps.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.apps_outlined, size: 42),
                  const SizedBox(height: 12),
                  Text(context.wmnT('no_applications_installed')),
                  const SizedBox(height: 4),
                  Text(
                    context.wmnT('no_applications_installed_help'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          )
        else
          ...apps.map(_applicationCard),
      ],
    );
  }

  Widget _applicationCard(WmnInstalledApplication app) {
    final diagnostic = registry.diagnose(app.manifest);
    final nativeWmn = app.sourceFramework == 'WMN';
    List<Map<String, Object?>> builds = const <Map<String, Object?>>[];
    if (nativeWmn) {
      try {
        builds = generator.builds(app.manifest.name, limit: 1);
      } catch (_) {}
    }
    final latestBuild = builds.isEmpty ? null : builds.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final identity = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(child: Text(_initial(app.manifest.title))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.manifest.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(_subtitle(app, diagnostic)),
                        if (latestBuild != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${context.wmnT('last_build')}: '
                            '${latestBuild['status']} • ${latestBuild['profile_name']}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(label: Text(app.sourceFramework)),
                  Chip(
                    label: Text(
                      diagnostic.compatible
                          ? app.status
                          : context.wmnT('incompatible'),
                    ),
                  ),
                  if (nativeWmn)
                    OutlinedButton.icon(
                      onPressed: () => _generatePackage(app),
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      label: Text(context.wmnT('generate_package')),
                    ),
                  if (nativeWmn)
                    IconButton(
                      tooltip: context.wmnT('build_history'),
                      onPressed: () => _showBuildHistory(app),
                      icon: const Icon(Icons.history_outlined),
                    ),
                  if (nativeWmn)
                    IconButton(
                      tooltip: context.wmnT('remove_application'),
                      onPressed: () => _removeApplication(
                        app.manifest.name,
                        app.manifest.title,
                      ),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 12),
                    Align(alignment: AlignmentDirectional.centerStart, child: actions),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 14),
                  Flexible(child: actions),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _generatePackage(WmnInstalledApplication app) async {
    try {
      final profiles = generator.profiles(app.manifest.name);
      if (!mounted) return;
      final profile = await showDialog<WmnApplicationBuildProfile>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.wmnT('generate_application_package')),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(app.manifest.title),
                const SizedBox(height: 12),
                ...profiles.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_buildModeIcon(entry.mode)),
                    title: Text(entry.name),
                    subtitle: Text(
                      '${wmnApplicationBuildModeToStorage(entry.mode)} • '
                      '${entry.targets.join(', ')}',
                    ),
                    onTap: () => Navigator.pop(dialogContext, entry),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.wmnT('cancel')),
            ),
          ],
        ),
      );
      if (profile == null || !mounted) return;
      final diagnostic = generator.validateBuild(app.manifest.name, profile: profile);
      if (diagnostic.errors.isNotEmpty) {
        await _showValidationDialog(diagnostic);
        return;
      }
      if (diagnostic.warnings.isNotEmpty) {
        final proceed = await _confirmWarnings(diagnostic.warnings);
        if (!proceed) return;
      }
      final result = generator.generatePackage(
        app.manifest.name,
        profileName: profile.name,
      );
      final save = await files.exportBytes(
        fileName: result.fileName,
        bytes: result.bytes,
        mimeType: 'application/zip',
        filters: const <WmnFileTypeFilter>[_packageFilter],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            save.saved
                ? '${context.wmnT('application_package_generated')} • SHA-256 ${result.sha256.substring(0, 12)}…'
                : (save.message ?? context.wmnT('application_package_generated')),
          ),
        ),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _importPackage() async {
    try {
      final selected = await files.pickFile(
        filters: const <WmnFileTypeFilter>[_packageFilter],
      );
      if (selected == null) return;
      final inspection = generator.inspectPackage(selected.bytes);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(context.wmnT('import_application_package')),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inspection.manifest.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text('${inspection.manifest.name} • ${inspection.manifest.version}'),
                    Text('WMN ${inspection.platformVersion} • Schema ${inspection.schemaVersion}'),
                    const SizedBox(height: 12),
                    Text(
                      '${context.wmnT('package_components')}: '
                      '${inspection.componentCounts.values.fold<int>(0, (sum, value) => sum + value)}',
                    ),
                    if (inspection.warnings.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...inspection.warnings.map(
                        (warning) => Text('• $warning'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(context.wmnT('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(context.wmnT('install')),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      final result = generator.installPackage(selected.bytes);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.updatedExistingApplication
                ? context.wmnT('application_package_updated')
                : context.wmnT('application_package_installed'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _showBuildHistory(WmnInstalledApplication app) async {
    final rows = generator.builds(app.manifest.name, limit: 30);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.wmnT('build_history')),
        content: SizedBox(
          width: 700,
          height: 420,
          child: rows.isEmpty
              ? Center(child: Text(context.wmnT('no_builds_yet')))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      leading: Icon(_buildStatusIcon('${row['status'] ?? ''}')),
                      title: Text('${row['profile_name']} • ${row['status']}'),
                      subtitle: Text(
                        '${row['app_version']} • ${row['created_at']}'
                        '${row['package_hash'] == null ? '' : '\n${row['package_hash']}'}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.wmnT('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showValidationDialog(
    WmnApplicationPackageDiagnostic diagnostic,
  ) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.wmnT('package_validation_failed')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: diagnostic.errors.map((error) => Text('• $error')).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.wmnT('close')),
            ),
          ],
        ),
      );

  Future<bool> _confirmWarnings(List<String> warnings) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.wmnT('package_validation_warnings')),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: warnings.map((warning) => Text('• $warning')).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.wmnT('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.wmnT('continue_action')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _createApplication() async {
    final name = TextEditingController();
    final title = TextEditingController();
    final version = TextEditingController(text: '0.1.0');
    final description = TextEditingController();
    final publisher = TextEditingController();
    final license = TextEditingController();
    final entryRoute = TextEditingController();
    final minimumPlatformVersion = TextEditingController();
    final requiredApplications = TextEditingController();
    final requiredSystemModules = TextEditingController();
    final capabilities = TextEditingController();
    final optionalCapabilities = TextEditingController();
    final capabilityProfile = TextEditingController();
    final modules = TextEditingController();
    final workspaces = TextEditingController();
    final routes = TextEditingController();
    final permissions = TextEditingController();
    final metadataContributions = TextEditingController();
    final targets = TextEditingController(text: 'windows, android, web');
    final assets = TextEditingController();

    try {
      final manifest = await showDialog<WmnAppManifest>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.wmnT('new_application')),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: context.wmnT('application_id'),
                      hintText: 'my_app',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: title,
                    decoration: InputDecoration(
                      labelText: context.wmnT('application_title'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: version,
                    decoration: InputDecoration(labelText: context.wmnT('version')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: context.wmnT('description'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: publisher,
                    decoration: InputDecoration(
                      labelText: context.wmnT('publisher'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: license,
                    decoration: InputDecoration(labelText: context.wmnT('license')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: entryRoute,
                    decoration: InputDecoration(
                      labelText: context.wmnT('entry_route'),
                      hintText: '/home',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: minimumPlatformVersion,
                    decoration: InputDecoration(
                      labelText: context.wmnT('minimum_platform_version'),
                      hintText: '3.21.2',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: requiredApplications,
                    decoration: InputDecoration(
                      labelText: context.wmnT('required_applications'),
                      hintText: 'shared_app',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: requiredSystemModules,
                    decoration: InputDecoration(
                      labelText: context.wmnT('required_system_modules'),
                      hintText: 'metadata, documents, reports',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: capabilities,
                    decoration: InputDecoration(
                      labelText: context.wmnT('required_capabilities'),
                      hintText: 'doctype, create, save',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: optionalCapabilities,
                    decoration: InputDecoration(
                      labelText: context.wmnT('optional_capabilities'),
                      hintText: 'print-contract, mobile.camera',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: capabilityProfile,
                    decoration: InputDecoration(
                      labelText: context.wmnT('capability_profile'),
                      hintText: 'minimal, windows_desktop, mobile_lite, web_client',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: modules,
                    decoration: InputDecoration(
                      labelText: context.wmnT('application_modules'),
                      hintText: 'Core, Operations',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: workspaces,
                    decoration: InputDecoration(
                      labelText: context.wmnT('application_workspaces'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: routes,
                    decoration: InputDecoration(
                      labelText: context.wmnT('application_routes'),
                      hintText: '/home, /reports',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: permissions,
                    decoration: InputDecoration(
                      labelText: context.wmnT('application_permissions'),
                      hintText: 'sample.read, sample.write',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: metadataContributions,
                    decoration: InputDecoration(
                      labelText: context.wmnT('metadata_contributions'),
                      hintText: 'Shared DocType',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: targets,
                    decoration: InputDecoration(
                      labelText: context.wmnT('platform_targets'),
                      hintText: 'windows, android, web',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: assets,
                    decoration: InputDecoration(
                      labelText: context.wmnT('application_assets'),
                      hintText: 'apps/my_app/assets/logo.png',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.wmnT('cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  WmnAppManifest(
                    name: name.text.trim(),
                    title: title.text.trim(),
                    version: version.text.trim(),
                    description: _optional(description.text),
                    publisher: _optional(publisher.text),
                    license: _optional(license.text),
                    entryRoute: _optional(entryRoute.text),
                    minimumPlatformVersion: _optional(minimumPlatformVersion.text),
                    requiredApplications: _csv(requiredApplications.text),
                    requiredSystemModules: _csv(requiredSystemModules.text),
                    requiredCapabilities: _csv(capabilities.text),
                    optionalCapabilities: _csv(optionalCapabilities.text),
                    capabilityProfile: _optional(capabilityProfile.text),
                    modules: _csv(modules.text),
                    workspaces: _csv(workspaces.text),
                    routes: _csv(routes.text),
                    permissions: _csv(permissions.text),
                    metadataContributions: _csv(metadataContributions.text),
                    platformTargets: _csv(targets.text),
                    assets: _csv(assets.text),
                  ),
                );
              },
              child: Text(context.wmnT('create')),
            ),
          ],
        ),
      );
      if (manifest == null) return;
      registry.register(manifest);
      generator.ensureDefaultProfiles(manifest.name);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.wmnT('application_registered'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      for (final controller in <TextEditingController>[
        name,
        title,
        version,
        description,
        publisher,
        license,
        entryRoute,
        minimumPlatformVersion,
        requiredApplications,
        requiredSystemModules,
        capabilities,
        optionalCapabilities,
        capabilityProfile,
        modules,
        workspaces,
        routes,
        permissions,
        metadataContributions,
        targets,
        assets,
      ]) {
        controller.dispose();
      }
    }
  }

  Future<void> _removeApplication(String name, String title) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.wmnT('remove_application')),
            content: Text('${context.wmnT('remove_application_confirm')}\n$title'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.wmnT('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.wmnT('remove')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      registry.remove(name);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  List<String> _csv(String value) => value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet()
      .toList(growable: false);

  String? _optional(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _subtitle(
    WmnInstalledApplication app,
    WmnApplicationDiagnostic diagnostic,
  ) {
    final parts = <String>['${app.manifest.name} • ${app.manifest.version}'];
    if (app.manifest.minimumPlatformVersion != null) {
      parts.add('WMN >= ${app.manifest.minimumPlatformVersion}');
    }
    if (app.manifest.requiredApplications.isNotEmpty) {
      parts.add('Apps: ${app.manifest.requiredApplications.join(' • ')}');
    }
    if (app.manifest.requiredSystemModules.isNotEmpty) {
      parts.add('Modules: ${app.manifest.requiredSystemModules.join(' • ')}');
    }
    if (app.manifest.requiredCapabilities.isNotEmpty) {
      parts.add('Capabilities: ${app.manifest.requiredCapabilities.join(' • ')}');
    }
    if (app.manifest.capabilityProfile != null) {
      parts.add('Profile: ${app.manifest.capabilityProfile}');
    }
    if (diagnostic.warnings.isNotEmpty) {
      parts.add('Warnings: ${diagnostic.warnings.join(' | ')}');
    }
    if (diagnostic.errors.isNotEmpty) {
      parts.add('Errors: ${diagnostic.errors.join(' | ')}');
    }
    return parts.join('\n');
  }

  String _initial(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? 'A' : normalized.substring(0, 1).toUpperCase();
  }

  IconData _buildModeIcon(WmnApplicationBuildMode mode) => switch (mode) {
        WmnApplicationBuildMode.development => Icons.code_outlined,
        WmnApplicationBuildMode.test => Icons.science_outlined,
        WmnApplicationBuildMode.release => Icons.verified_outlined,
      };

  IconData _buildStatusIcon(String status) => switch (status.toUpperCase()) {
        'READY' => Icons.check_circle_outline,
        'FAILED' => Icons.error_outline,
        'IMPORTED' => Icons.download_done_outlined,
        _ => Icons.hourglass_empty,
      };
}
