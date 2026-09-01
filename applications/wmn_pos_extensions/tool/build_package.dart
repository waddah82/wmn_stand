import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

const _componentNames = <String>[
  'modules',
  'doctypes',
  'doctype_fields',
  'doctype_permissions',
  'list_views',
  'custom_fields',
  'property_overrides',
  'numbering_series',
  'roles',
  'permissions',
  'role_permissions',
  'workspaces',
  'workspace_items',
  'pages',
  'reports',
  'report_filters',
  'report_columns',
  'print_formats',
  'client_scripts',
  'server_scripts',
  'workflows',
  'workflow_states',
  'workflow_transitions',
  'method_bindings',
  'hook_bindings',
  'number_cards',
  'dashboard_charts',
];

void main() {
  final appRoot = _locateAppRoot();
  final manifest = _readMap(File('${appRoot.path}/manifest.json'));
  final profile = _readMap(File('${appRoot.path}/profile.json'));
  final appName = '${manifest['name'] ?? ''}'.trim();
  final appVersion = '${manifest['version'] ?? ''}'.trim();
  if (appName.isEmpty || appVersion.isEmpty) {
    throw StateError('manifest.json must contain name and version.');
  }

  final entries = <String, Uint8List>{};
  final counts = <String, int>{};
  for (final component in _componentNames) {
    final file = File('${appRoot.path}/metadata/$component.json');
    if (!file.existsSync()) {
      throw StateError('Missing metadata component: ${file.path}');
    }
    final rows = _readList(file);
    counts[component] = rows.length;
    entries['metadata/$component.json'] = _jsonBytes(rows);
  }

  final editableSources = _readList(File('${appRoot.path}/sources/index.json'));
  final sourceIndex = <Map<String, Object?>>[];
  for (final row in editableSources) {
    final storageKey = '${row['storage_key'] ?? ''}'.trim();
    final relativePath = '${row['file'] ?? ''}'.trim().replaceAll('\\', '/');
    if (storageKey.isEmpty || relativePath.isEmpty || relativePath.startsWith('/')) {
      throw StateError('Invalid source index row: $row');
    }
    final file = File('${appRoot.path}/$relativePath');
    if (!file.existsSync()) throw StateError('Managed source is missing: ${file.path}');
    final bytes = file.readAsBytesSync();
    final hash = sha256.convert(bytes).toString();
    final leaf = storageKey.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final archivePath = 'sources/$hash-$leaf';
    entries[archivePath] = Uint8List.fromList(bytes);
    sourceIndex.add(<String, Object?>{
      'storage_key': storageKey,
      'archive_path': archivePath,
      'sha256': hash,
      'size': bytes.length,
    });
  }
  sourceIndex.sort((a, b) => '${a['storage_key']}'.compareTo('${b['storage_key']}'));
  entries['metadata/sources.json'] = _jsonBytes(sourceIndex);
  entries['assets/index.json'] = _jsonBytes(const <Object?>[]);

  final targets = (profile['targets'] is List ? profile['targets'] as List : const <Object?>['all'])
      .map((value) => '$value'.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  entries['targets/index.json'] = _jsonBytes(<Object?>[
    for (final target in targets.isEmpty ? const <String>['all'] : targets)
      <String, Object?>{
        'target': target,
        'application_id': appName,
        'display_name': '${manifest['title'] ?? appName}',
        'version': appVersion,
        'entry_route': manifest['entry_route'],
        'host_requirements': <String, Object?>{},
      },
  ]);

  counts['managed_sources'] = sourceIndex.length;
  counts['assets'] = 0;
  final envelope = <String, Object?>{
    'package_format': 'wmn.application',
    'package_format_version': 1,
    'generated_by': 'WMN POS Extensions editable application source',
    'platform_version': '3.25.0+127',
    'schema_version': 36,
    'build_id': const Uuid().v4(),
    'built_at': DateTime.now().toUtc().toIso8601String(),
    'profile': profile,
    'manifest': manifest,
    'component_counts': counts,
    'warnings': const <String>[],
  };
  entries['wmn_app.json'] = _jsonBytes(envelope);

  final checksumBuffer = StringBuffer();
  final checksumPaths = entries.keys.toList()..sort();
  for (final path in checksumPaths) {
    checksumBuffer.writeln('${sha256.convert(entries[path]!)}  $path');
  }
  entries['checksums.sha256'] = Uint8List.fromList(utf8.encode(checksumBuffer.toString()));

  final archive = Archive();
  final paths = entries.keys.toList()..sort();
  for (final path in paths) {
    final bytes = entries[path]!;
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) throw StateError('ZIP encoding failed.');

  final dist = Directory('${appRoot.path}/dist')..createSync(recursive: true);
  final output = File('${dist.path}/$appName-$appVersion.zip')..writeAsBytesSync(encoded, flush: true);
  final packageHash = sha256.convert(output.readAsBytesSync()).toString();
  stdout.writeln('Built standard ZIP: ${output.path}');
  stdout.writeln('Bytes: ${output.lengthSync()}');
  stdout.writeln('SHA-256: $packageHash');
}

Directory _locateAppRoot() {
  var current = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = Directory('${current.path}/applications/wmn_pos_extensions');
    if (File('${candidate.path}/manifest.json').existsSync()) return candidate;
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  final script = File.fromUri(Platform.script).absolute;
  final candidate = script.parent.parent;
  if (File('${candidate.path}/manifest.json').existsSync()) return candidate;
  throw StateError('Cannot locate applications/wmn_pos_extensions from the current directory.');
}

Map<String, Object?> _readMap(File file) {
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map) throw StateError('${file.path} must contain a JSON object.');
  return Map<String, Object?>.from(value);
}

List<Map<String, Object?>> _readList(File file) {
  final value = jsonDecode(file.readAsStringSync());
  if (value is! List) throw StateError('${file.path} must contain a JSON array.');
  return value.map((row) {
    if (row is! Map) throw StateError('${file.path} contains a non-object row.');
    return Map<String, Object?>.from(row);
  }).toList(growable: false);
}

Uint8List _jsonBytes(Object? value) => Uint8List.fromList(
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(value)}\n'),
    );
