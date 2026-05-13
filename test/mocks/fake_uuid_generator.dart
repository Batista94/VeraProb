import 'package:veraprob/domain/shared/uuid_generator.dart';

/// Deterministic UUID generator for testing (INV-15).
/// Returns sequential IDs: 'fake-uuid-0', 'fake-uuid-1', etc.
class FakeUuidGenerator implements IUuidGenerator {
  int _counter = 0;

  @override
  String v4() => 'fake-uuid-${_counter++}';

  /// Resets the counter for test isolation.
  void reset() => _counter = 0;
}
