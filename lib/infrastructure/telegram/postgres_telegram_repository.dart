import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/sla_audit/telegram/i_telegram_repository.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_binding_token.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase/Postgres implementation of [ITelegramRepository].
///
/// INV-1: All queries filter by organization_id.
/// INV-7: No DELETE or UPDATE calls — only INSERT and SELECT.
class PostgresTelegramRepository extends BasePostgresRepository
    implements ITelegramRepository {
  PostgresTelegramRepository(super.client);

  @override
  Future<TelegramBindingToken> createBindingToken(
    TelegramBindingToken token,
  ) async {
    try {
      await client.from('telegram_binding_tokens').insert({
        'id': token.id,
        'organization_id': token.organizationId,
        'driver_id': token.driverId,
        'created_by_user_id': token.createdByUserId,
        'code': token.code,
        'expires_at_utc': token.expiresAtUtc.toIso8601String(),
        'created_at_utc': token.createdAtUtc.toIso8601String(),
      });
      return token;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'telegram_binding_token',
      );
    }
  }

  @override
  Future<TelegramBindingToken?> findLatestTokenForDriver({
    required String driverId,
    required String organizationId,
  }) async {
    try {
      final row = await client
          .from('telegram_binding_tokens')
          .select(
            'id, organization_id, driver_id, created_by_user_id, '
            'code, expires_at_utc, used_at_utc, created_at_utc',
          )
          .eq('driver_id', driverId)
          .eq('organization_id', organizationId)
          .order('created_at_utc', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) return null;
      return _tokenFromRow(row);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'telegram_binding_token',
      );
    }
  }

  @override
  Future<bool> hasActiveBinding({
    required String driverId,
    required String organizationId,
  }) async {
    try {
      final row = await client
          .from('telegram_chat_bindings')
          .select('id')
          .eq('driver_id', driverId)
          .eq('organization_id', organizationId)
          .isFilter('unbound_at_utc', null)
          .limit(1)
          .maybeSingle();
      return row != null;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'telegram_chat_binding',
      );
    }
  }

  TelegramBindingToken _tokenFromRow(Map<String, dynamic> row) {
    return TelegramBindingToken(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      driverId: row['driver_id'] as String,
      createdByUserId: row['created_by_user_id'] as String,
      code: row['code'] as String,
      expiresAtUtc: DateTime.parse(row['expires_at_utc'] as String).toUtc(),
      usedAtUtc: row['used_at_utc'] != null
          ? DateTime.parse(row['used_at_utc'] as String).toUtc()
          : null,
      createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
    );
  }
}
