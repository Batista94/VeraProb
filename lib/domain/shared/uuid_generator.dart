import 'package:uuid/uuid.dart';

/// Abstraction over UUID generation for deterministic replay (INV-15).
abstract class IUuidGenerator {
  String v4();
}

/// Production implementation using `package:uuid`.
class UuidGenerator implements IUuidGenerator {
  const UuidGenerator();

  @override
  String v4() => const Uuid().v4();
}
