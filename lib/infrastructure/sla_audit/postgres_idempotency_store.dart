import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/idempotency_key.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/idempotency_registration_result.dart';
import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [IIdempotencyStore].
///
/// Uses Supabase RPC functions for atomic idempotency key management.
class PostgresIdempotencyStore extends BasePostgresRepository
    implements IIdempotencyStore {
  PostgresIdempotencyStore(super.client);

  @override
  Future<IdempotencyRegistrationResult> tryRegister(
    IdempotencyKey key, {
    int staleThresholdMinutes = 5,
  }) async {
    try {
      final result = await client.rpc(
        'try_acquire_idempotency_key',
        params: {
          'p_id': key.id,
          'p_user_id': key.userId,
          'p_command_path': key.commandPath,
          'p_organization_id': key.organizationId,
          'p_stale_threshold_min': staleThresholdMinutes,
        },
      );

      final response = result as Map<String, dynamic>;
      final acquired = !(response['hit'] as bool);
      
      return IdempotencyRegistrationResult(
        acquired: acquired,
        key: _mapToEntity(response),
      );
    } on PostgrestException catch (e) {
      if (e.code == 'unique_violation' || e.message.contains('IdempotencyProcessingException')) {
        throw IdempotencyProcessingException(
          idempotencyKey: key.id,
          commandPath: key.commandPath,
        );
      }
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'idempotency_key',
        resourceId: key.id,
      );
    }
  }

  @override
  Future<IdempotencyKey?> findById(String id, {required String userId}) async {
    try {
      final data = await client
          .from('idempotency_keys')
          .select()
          .eq('id', id)
          .eq('user_id', userId)
          .maybeSingle();

      if (data == null) return null;
      return _mapToEntity(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'idempotency_key',
        resourceId: id,
      );
    }
  }

  @override
  Future<void> markCompleted({
    required String id,
    required String userId,
    required int responseCode,
    required Map<String, dynamic> responseBody,
    required DateTime nowUtc,
  }) async {
    try {
      await client.rpc(
        'complete_idempotency_key',
        params: {
          'p_id': id,
          'p_user_id': userId,
          'p_response_code': responseCode,
          'p_response_body': _canonicalize(responseBody),
        },
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'idempotency_key',
        resourceId: id,
      );
    }
  }

  @override
  Future<void> markError({
    required String id,
    required String userId,
    required int responseCode,
    required DateTime nowUtc,
    Map<String, dynamic>? responseBody,
  }) async {
    try {
      await client.rpc(
        'fail_idempotency_key',
        params: {
          'p_id': id,
          'p_user_id': userId,
          'p_response_code': responseCode,
          'p_response_body': responseBody != null ? _canonicalize(responseBody) : null,
        },
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'idempotency_key',
        resourceId: id,
      );
    }
  }

  @override
  Future<int> cleanupExpired({int daysThreshold = 30}) async {
    try {
      final result = await client.rpc(
        'cleanup_expired_idempotency',
        params: {'days_threshold': daysThreshold},
      );
      return (result as num).toInt();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'idempotency_key',
        resourceId: 'cleanup',
      );
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Map<String, dynamic> _canonicalize(Map<String, dynamic> payload) {
    final sorted = _sortKeysRecursive(payload);
    return sorted as Map<String, dynamic>;
  }

  dynamic _sortKeysRecursive(dynamic obj) {
    if (obj == null) return null;
    if (obj is DateTime) return obj.toUtc().toIso8601String();
    if (obj is Map<String, dynamic>) {
      final sorted = <String, dynamic>{};
      final keys = obj.keys.toList()..sort();
      for (final key in keys) {
        sorted[key] = _sortKeysRecursive(obj[key]);
      }
      return sorted;
    }
    if (obj is List) return obj.map(_sortKeysRecursive).toList();
    return obj;
  }

  IdempotencyKey _mapToEntity(Map<String, dynamic> row) {
    return IdempotencyKey(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      commandPath: row['command_path'] as String,
      organizationId: row['organization_id'] as String,
      status: row['status'] as String,
      responseCode: (row['response_code'] as num?)?.toInt(),
      responseBody: _parseJsonb(row['response_body']),
      createdAtUtc: _parseUtc(row['created_at_utc'], 'created_at_utc'),
      completedAtUtc: row['completed_at_utc'] != null
          ? _parseUtc(row['completed_at_utc'], 'completed_at_utc')
          : null,
      staleThresholdMinutes: (row['stale_threshold_minutes'] as num?)?.toInt() ?? 5,
    );
  }

  Map<String, dynamic>? _parseJsonb(dynamic value) {
    if (value == null) return null;
    if (value is String) return jsonDecode(value) as Map<String, dynamic>?;
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  DateTime _parseUtc(dynamic raw, String fieldName) {
    if (raw == null) throw StateError('Timestamp "$fieldName" is null');
    if (raw is! String) throw StateError('Timestamp "$fieldName" must be string');
    final normalized = (raw.endsWith('Z') || raw.contains('+')) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toUtc();
  }
}
