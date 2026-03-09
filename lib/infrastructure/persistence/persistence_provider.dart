import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'persistence_mode.dart';

/// Provider that holds the current persistence mode of the application.
/// Defaults to [PersistenceMode.inMemory].
///
/// This is the only Core persistence concern. Module-specific repository
/// factories live in their respective module infrastructure layers
/// (e.g., lib/infrastructure/sla_audit/sla_persistence_provider.dart).
final persistenceModeProvider = Provider<PersistenceMode>((ref) {
  return PersistenceMode.inMemory;
});
