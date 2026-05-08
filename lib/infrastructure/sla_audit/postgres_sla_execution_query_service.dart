import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// Postgres implementation for [SlaExecutionQueryService].
/// Extracts flat DTOs directly from the `execution_states` table.
/// Purely read-only, strict separation from Domain.
class SlaExecutionQueryServicePostgres implements SlaExecutionQueryService {
  final SupabaseClient _client;
  final IDateTimeProvider _dateTimeProvider;

  SlaExecutionQueryServicePostgres(this._client, this._dateTimeProvider);

  @override
  Future<SlaExecutionSummary> getSummary({
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client
        .from('execution_states')
        .select('status, contractual_value_cents, no_show_penalty_multiplier')
        .eq('organization_id', organizationId);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    final rows = await query.order('created_at_utc', ascending: false);

    int pending = 0;
    int inTransit = 0;
    int executed = 0;
    int noShow = 0;
    int evidenceGap = 0;
    Money protectedRevenue = const Money(0);
    Money revenueAtRisk = const Money(0);
    Money lostRevenue = const Money(0);

    for (var row in rows) {
      final String statusStr;
      final int cents;
      final int penaltyBps;

      try {
        statusStr = row['status'] as String;
        cents = (row['contractual_value_cents'] as num).toInt();
        // INV-18: no ?? default â€” null multiplier must throw, not silently
        // produce a 1x penalty that masks missing contract data.
        penaltyBps = ((row['no_show_penalty_multiplier'] as num) * 10000)
            .round();
      } on TypeError catch (e) {
        throw IntegrityException(
          'Corrupt execution_states row: malformed numeric or string field â€” '
          'expected status (String), contractual_value_cents (num), '
          'no_show_penalty_multiplier (num). Details: $e',
        );
      }

      final val = Money(cents);

      if (statusStr == ExecutionStatus.planned.name) {
        pending++;
        revenueAtRisk = revenueAtRisk + val;
      } else if (statusStr == ExecutionStatus.completed.name) {
        executed++;
        protectedRevenue = protectedRevenue + val;
      } else if (statusStr == ExecutionStatus.failed.name) {
        noShow++;
        lostRevenue = lostRevenue + val.multiplyByBps(penaltyBps);
      } else if (statusStr == ExecutionStatus.completedWithGaps.name) {
        evidenceGap++;
        lostRevenue = lostRevenue + val;
      } else if (statusStr == ExecutionStatus.inTransit.name) {
        inTransit++;
        revenueAtRisk = revenueAtRisk + val;
      } else if (statusStr == ExecutionStatus.inhibited.name) {
        // inhibited: obligation suppressed — no financial impact
      }
    }

    return SlaExecutionSummary(
      contractId: contractId,
      totalPlanned: pending,
      totalInTransit: inTransit,
      totalCompleted: executed,
      totalFailed: noShow,
      totalCompletedWithGaps: evidenceGap,
      generatedAtUtc: _dateTimeProvider.nowUtc(),
      protectedRevenue: protectedRevenue.cents,
      revenueAtRisk: revenueAtRisk.cents,
      lostRevenue: lostRevenue.cents,
    );
  }

  @override
  Future<List<SlaExecutionItemView>> listByStatus(
    ExecutionStatus status, {
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client
        .from('execution_states')
        .select()
        .eq('organization_id', organizationId)
        .eq('status', status.name);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    // Limit applied to prevent full ledger scanning into memory
    final rows = await query
        .order('window_start_utc', ascending: true)
        .limit(500);

    return rows.map((row) {
      return _mapRow(row, status);
    }).toList();
  }

  @override
  Future<SlaExecutionItemView?> findBySetId(
    String setId, {
    required String organizationId,
  }) async {
    final row = await _client
        .from('execution_states')
        .select()
        .eq('organization_id', organizationId)
        .eq('set_id', setId)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;

    final String statusStr;
    try {
      statusStr = row['status'] as String;
    } on TypeError catch (e) {
      throw IntegrityException(
        'Corrupt execution_states row: status field is null or not a String '
        'in set_id=${row['set_id']}. Details: $e',
        field: 'status',
      );
    }

    return _mapRow(
      row,
      IntegrityException.shield(ExecutionStatus.values, statusStr, 'status'),
    );
  }

  @override
  Future<List<SlaExecutionItemView>> listByWindow(
    DateTime startUtc,
    DateTime endUtc, {
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client
        .from('execution_states')
        .select()
        .eq('organization_id', organizationId)
        .gte('window_start_utc', startUtc.toUtc().toIso8601String())
        .lt('window_start_utc', endUtc.toUtc().toIso8601String());

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    final rows = await query
        .order('window_start_utc', ascending: true)
        .limit(500);

    return rows.map((row) {
      final String statusStr;
      try {
        statusStr = row['status'] as String;
      } on TypeError catch (e) {
        throw IntegrityException(
          'Corrupt execution_states row: status field is null or not a String '
          'in set_id=${row['set_id']}. Details: $e',
          field: 'status',
        );
      }
      return _mapRow(
        row,
        IntegrityException.shield(ExecutionStatus.values, statusStr, 'status'),
      );
    }).toList();
  }

  /// Normalizes a Postgres timestamp string to a UTC [DateTime].
  ///
  /// Postgres `TIMESTAMP WITHOUT TIME ZONE` columns return naive strings
  /// (e.g., `'2026-04-09T20:00:00'`) without any timezone indicator.
  /// Dart's `DateTime.parse()` interprets those as **local** time, then
  /// `.toUtc()` applies the local offset â€” causing silent drift in production
  /// when the server runs in a non-UTC locale (INV-9 violation).
  ///
  /// By appending `'Z'` before parsing, we treat all naive strings as UTC,
  /// matching the Postgres behaviour on a UTC-configured server.
  static DateTime _parseUtc(String s) {
    if (!s.endsWith('Z') && !RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s)) {
      return DateTime.parse('${s}Z');
    }
    return DateTime.parse(s).toUtc();
  }

  /// Maps a raw Postgres row to an [SlaExecutionItemView].
  ///
  /// **INV-9:** All timestamp strings are normalized via [_parseUtc] so that
  /// naive strings (no timezone suffix) from Postgres are treated as UTC â€”
  /// not as the local system time â€” preventing silent clock drift.
  ///
  /// **INV-18:** Catches `TypeError` and `FormatException` from corrupt
  /// JSONB/numeric/date fields and re-throws as semantic [IntegrityException].
  /// No `?? defaults` are used for critical financial fields â€” a missing
  /// multiplier must fail loudly, not silently produce wrong penalties.
  SlaExecutionItemView _mapRow(
    Map<String, dynamic> row,
    ExecutionStatus status,
  ) {
    try {
      return SlaExecutionItemView(
        setId: row['set_id'] as String,
        contractId: row['contract_id'] as String,
        status: status,
        windowStartUtc: _parseUtc(row['window_start_utc'] as String),
        windowEndUtc: _parseUtc(row['window_end_utc'] as String),
        plannedVehicleId: row['planned_vehicle_id'] as String?,
        boundVehicleId: row['bound_vehicle_id'] as String?,
        boundAtUtc: row['binding_timestamp_utc'] != null
            ? _parseUtc(row['binding_timestamp_utc'] as String)
            : null,
        startLatitude: (row['start_latitude'] as num)
            .toDouble(), // Physical Metric - Double Required
        startLongitude: (row['start_longitude'] as num)
            .toDouble(), // Physical Metric - Double Required
        startRadiusMeters: (row['start_radius_meters'] as num).toInt(),
        contractualValue: (row['contractual_value_cents'] as num).toInt(),
        // INV-18: no ?? default â€” null multiplier must throw, not silently
        // produce a 1x (100%) penalty that masks missing contract data.
        noShowPenaltyBps: ((row['no_show_penalty_multiplier'] as num) * 10000)
            .round(),
      );
    } on TypeError catch (e) {
      throw IntegrityException(
        'Corrupt execution_states row: malformed field in set_id=${row['set_id']} â€” '
        'expected valid types for all columns. Details: $e',
        field: 'row_mapping',
      );
    } on FormatException catch (e) {
      throw IntegrityException(
        'Corrupt execution_states row: invalid date string in set_id=${row['set_id']} â€” '
        'all timestamp columns must be ISO-8601. Details: $e',
        field: 'timestamp',
      );
    }
  }
}
