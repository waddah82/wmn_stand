import 'package:flutter_test/flutter_test.dart';
import 'package:wmn_standalone/platform/scripts/wmn_script_runtime.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_adapter.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_service.dart';

void main() {
  group('WMN Script/Storage Runtime', () {
    late WmnStorageService storage;
    late WmnScriptRuntime scripts;

    setUp(() {
      storage = WmnStorageService(WmnMemoryStorageAdapter());
      scripts = WmnScriptRuntime(storage: storage);
    });

    test('native handlers are compiled registrations, not database script blobs', () {
      scripts.registerNativeHandler('demo.total', (context) {
        final a = context['a'] as int;
        final b = context['b'] as int;
        return a + b;
      });

      expect(scripts.hasNativeHandler('demo.total'), isTrue);
      expect(scripts.executeNative('demo.total', const {'a': 4, 'b': 6}), 10);
      expect(
        () => scripts.executeNative('missing.handler', const {}),
        throwsStateError,
      );
    });

    test('managed script source is resolved from storage through an explicit executor', () {
      scripts.saveSource(
        path: 'apps/demo/reports/managed.wmn',
        source: 'return filters.total;',
      );
      scripts.registerManagedExecutor('wmn-test', (source, context) {
        return <String, Object?>{
          'source': source,
          'total': context['total'],
        };
      });

      expect(scripts.sourceExists('apps/demo/reports/managed.wmn'), isTrue);
      final result = scripts.executeStored(
        path: 'apps/demo/reports/managed.wmn',
        language: 'wmn-test',
        context: const {'total': 42},
      ) as Map<String, Object?>;

      expect(result['source'], 'return filters.total;');
      expect(result['total'], 42);
    });

    test('managed execution is denied when no language executor is registered', () {
      scripts.saveSource(path: 'apps/demo/scripts/rule.wmn', source: 'rule');
      expect(
        () => scripts.executeStored(
          path: 'apps/demo/scripts/rule.wmn',
          language: 'unknown',
        ),
        throwsStateError,
      );
    });

    test('storage keys cannot escape the WMN storage root', () {
      expect(
        () => scripts.saveSource(path: '../outside.wmn', source: 'blocked'),
        throwsStateError,
      );
    });
  });
}
