import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/audit/audit_service.dart';
import 'package:veraprob/infrastructure/audit/in_memory_audit_service.dart';
import 'package:veraprob/infrastructure/audit/postgres_audit_service.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final auditServiceProvider = Provider<AuditService>((ref) {
  final mode = ref.watch(persistenceModeProvider);

  switch (mode) {
    case PersistenceMode.inMemory:
      return InMemoryAuditService();
    case PersistenceMode.postgres:
      final client = ref.watch(supabaseClientProvider);
      return PostgresAuditService(client);
  }
});
