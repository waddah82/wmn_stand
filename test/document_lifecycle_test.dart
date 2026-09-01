import 'package:flutter_test/flutter_test.dart';
import 'package:wmn_standalone/core/documents/document_lifecycle.dart';

void main() {
  const engine = DocumentLifecycleEngine();

  test('document lifecycle allows draft submit and submitted cancel', () {
    expect(
      () => engine.ensureTransition(
        from: DocumentLifecycleStatus.draft,
        to: DocumentLifecycleStatus.submitted,
      ),
      returnsNormally,
    );
    expect(
      () => engine.ensureTransition(
        from: DocumentLifecycleStatus.submitted,
        to: DocumentLifecycleStatus.cancelled,
      ),
      returnsNormally,
    );
  });

  test('document lifecycle rejects cancel directly from draft', () {
    expect(
      () => engine.ensureTransition(
        from: DocumentLifecycleStatus.draft,
        to: DocumentLifecycleStatus.cancelled,
      ),
      throwsStateError,
    );
  });
}
