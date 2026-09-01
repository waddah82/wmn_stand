import 'package:flutter_test/flutter_test.dart';

import '../tool/benchmark_r315_transition.dart' as transition_benchmark;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('R3.15 transition benchmark stays inside broad regression guardrails', () async {
    final results = await transition_benchmark.runR315TransitionBenchmark();

    for (final entry in results.entries) {
      // ignore: avoid_print
      print('R315_BENCHMARK ${entry.key}=${entry.value}');
    }

    expect(results['small_source_first_read_us']!, lessThan(250000));
    expect(results['small_source_cached_10000_reads_us']!, lessThan(2000000));
    expect(results['file_10mb_async_write_ms']!, lessThan(15000));
    expect(results['file_10mb_async_read_ms']!, lessThan(15000));
    expect(results['query_report_5000_rows_total_ms']!, lessThan(5000));
    expect(results['source_units_1000_metadata_list_ms']!, lessThan(5000));
    expect(results['source_unit_single_hydration_us']!, lessThan(1000000));

    // The engine-only timing must be present and non-negative. The end-to-end
    // Query Report budget above is the actual transition guardrail.
    expect(results['query_report_engine_ms']!, greaterThanOrEqualTo(0));
  });
}
