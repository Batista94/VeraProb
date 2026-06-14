import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/sanction_acknowledgement_command_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation: single write path via the
/// `acknowledge_sanction_internal` SECURITY DEFINER RPC. All concurrency,
/// authority (TENANT_ADMIN), and atomicity live in the DB transaction.
///
/// Error mapping: `42501` (non-applied / wrong-role / NULL-JWT) →
/// [mapPostgrestToDomainException] → opaque domain failure (INV-26).
class PostgresSanctionAcknowledgementCommandRepository
    extends BasePostgresRepository
    implements SanctionAcknowledgementCommandRepository {
  PostgresSanctionAcknowledgementCommandRepository(super.client);

  @override
  Future<String> acknowledgeInternal({
    required String organizationId,
    required String queueEntryId,
    required String acknowledgedByUserId,
    String? notes,
  }) async {
    try {
      final id = await client.rpc<String>(
        'acknowledge_sanction_internal',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_acknowledged_by': acknowledgedByUserId,
          'p_notes': notes,
        },
      );
      return id;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e);
    }
  }
}
