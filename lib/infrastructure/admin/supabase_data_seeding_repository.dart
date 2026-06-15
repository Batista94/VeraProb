import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/admin/data_seeding_repository.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

class SupabaseDataSeedingRepository
    with PostgresErrorInterceptor
    implements DataSeedingRepository {
  final SupabaseClient _supabase;
  final IDateTimeProvider _dateTimeProvider;

  SupabaseDataSeedingRepository(this._supabase, this._dateTimeProvider);

  @override
  Future<void> seedDrivers(String organizationId) async {
    final drivers = [
      {'full_name': 'João Silva', 'license_number': '11122233344'},
      {'full_name': 'Maria Oliveira', 'license_number': '55566677788'},
      {'full_name': 'Carlos Santos', 'license_number': '99988877766'},
    ];

    for (var d in drivers) {
      try {
        final exists = await _supabase
            .from('drivers')
            .select()
            .eq('license_number', d['license_number']!)
            .eq('organization_id', organizationId)
            .maybeSingle();

        if (exists == null) {
          final payload = Map<String, dynamic>.from(d);
          payload['organization_id'] = organizationId;
          await _supabase.from('drivers').insert(payload);
        }
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }
    }
  }

  @override
  Future<void> seedRoutes(String organizationId) async {
    final routes = [
      {
        'gtfs_route_id': '809U-10',
        'short_name': '809U',
        'long_name': 'Cidade Universitária / Metrô Barra Funda',
        'agency_id': 'SPTRANS',
      },
      {
        'gtfs_route_id': '875C-10',
        'short_name': '875C',
        'long_name': 'Term. Lapa / Metrô Santa Cruz',
        'agency_id': 'SPTRANS',
      },
      {
        'gtfs_route_id': '917H-10',
        'short_name': '917H',
        'long_name': 'Term. Pirituba / Metrô Vila Mariana',
        'agency_id': 'SPTRANS',
      },
      {
        'gtfs_route_id': '701U-10',
        'short_name': '701U',
        'long_name': 'Cidade Universitária / Metrô Santana',
        'agency_id': 'SPTRANS',
      },
    ];

    for (var r in routes) {
      try {
        final exists = await _supabase
            .from('routes')
            .select()
            .eq('gtfs_route_id', r['gtfs_route_id']!)
            .eq('organization_id', organizationId)
            .maybeSingle();

        if (exists == null) {
          final payload = Map<String, dynamic>.from(r);
          payload['organization_id'] = organizationId;
          await _supabase.from('routes').insert(payload);
        }
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }
    }
  }

  @override
  Future<void> seedHistoricalData(String organizationId) async {
    // 1. Get or create a contract
    Map<String, dynamic>? contract;
    try {
      contract = await _supabase
          .from('contracts')
          .select()
          .eq('organization_id', organizationId)
          .limit(1)
          .maybeSingle();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
    }

    if (contract == null) {
      Map<String, dynamic>? contractor;
      try {
        contractor = await _supabase
            .from('contractors')
            .select()
            .limit(1)
            .maybeSingle();
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }

      try {
        final newContract = await _supabase
            .from('contracts')
            .insert({
              'organization_id': organizationId,
              'name': 'Contrato de Teste Histórico',
              'contractor_name': contractor?['name'] ?? 'Empresa Beta',
              'valid_from_utc': _dateTimeProvider
                  .nowUtc()
                  .subtract(const Duration(days: 30))
                  .toIso8601String(),
              'valid_until_utc': _dateTimeProvider
                  .nowUtc()
                  .add(const Duration(days: 30))
                  .toIso8601String(),
              'status': 'active',
              'financial_ceiling_cents': 500000,
            })
            .select()
            .single();
        contract = newContract;
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }
    }

    // 2. Clear previous historical test data
    try {
      // trips_audit is append-only (no DELETE policy per INV-3/INV-22 hardening).
      // We skip deletion to prevent 42501 insufficient_privilege.
      // Duplicate trips in dev are acceptable.
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
    }

    // 3. Create trips for yesterday
    final yesterday = DateTime.utc(2026, 03, 16);
    List<dynamic> routeList;
    List<dynamic> driverList;
    try {
      routeList = await _supabase
          .from('routes')
          .select('id')
          .eq('organization_id', organizationId)
          .limit(2);
      driverList = await _supabase
          .from('drivers')
          .select('id')
          .eq('organization_id', organizationId)
          .limit(2);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
    }

    if (routeList.isEmpty || driverList.isEmpty) return;

    final tripScenarios = [
      {'hour': 8, 'status': 'completed', 'penalty': 0},
      {'hour': 10, 'status': 'completed', 'penalty': 15000},
      {'hour': 14, 'status': 'completed', 'penalty': 0},
      {'hour': 16, 'status': 'completed', 'penalty': 5000},
    ];

    for (var scenario in tripScenarios) {
      final startTime = yesterday.add(Duration(hours: scenario['hour'] as int));
      final endTime = startTime.add(const Duration(hours: 1));

      try {
        final trip = await _supabase
            .from('trips_audit')
            .insert({
              'organization_id': organizationId,
              'route_id': routeList[0]['id'],
              'driver_id': driverList[0]['id'],
              'start_time': startTime.toIso8601String(),
              'end_time': endTime.toIso8601String(),
              'status': 'completed',
              'source_type': 'history_seed',
            })
            .select()
            .single();

        final tripId = trip['id'];

        // 4. Create Ledger Entries
        await _supabase.from('sla_audit_ledger_v2').insert({
          'organization_id': organizationId,
          'occurred_at_utc': endTime.toIso8601String(),
          'type': 'VERDICT_SEALED',
          'set_id': tripId,
          'operator_id': 'system_seeder',
          'new_value': scenario['penalty'] == 0 ? 'COMPLIANT' : 'NON_COMPLIANT',
          'payload': {'penalty_cents': scenario['penalty']},
        });
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }
    }

    // 5. Create Financial Snapshots for the last 15 days
    final now = _dateTimeProvider.nowUtc();
    for (int d = 1; d <= 15; d++) {
      final opDate = now.subtract(Duration(days: d));
      final dateStr = opDate.toIso8601String().split('T').first;

      // Vary calculations slightly so the graphs look real and full:
      // Base revenue: between 300,000 and 600,000 cents
      final contracted = 300000 + (d * 20000) % 300000;
      final lost = (d % 3 == 0)
          ? (contracted * 0.1).round()
          : ((d % 5 == 0) ? (contracted * 0.2).round() : 0);
      final risk = (d % 4 == 0) ? (contracted * 0.15).round() : 0;
      final protected = contracted - lost - risk;
      final lossBps = ((lost / contracted) * 10000).round();
      final riskBps = ((risk / contracted) * 10000).round();
      final obligations = 5 + d % 5;
      final executed = obligations - (lost > 0 ? 1 : 0);

      try {
        await _supabase.from('contractual_financial_snapshot').insert({
          'id': const Uuid().v4(),
          'organization_id': organizationId,
          'contract_id': contract['id'],
          'operational_date_utc': dateStr,
          'operational_timezone': 'America/Sao_Paulo',
          'closed_at_utc': now.toIso8601String(),
          'total_contracted_revenue_cents': contracted,
          'protected_revenue_cents': protected,
          'revenue_at_risk_cents': risk,
          'lost_revenue_cents': lost,
          'risk_percentage_bps': riskBps,
          'loss_percentage_bps': lossBps,
          'total_obligations': obligations,
          'executed_count': executed,
          'engine_version': 1,
        });
      } on PostgrestException catch (e) {
        // Skip duplicate errors gracefully
        if (e.code != '23505') {
          throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
        }
      }
    }

    // 6. Seed some RAW Telemetry
    await _seedVehicles(organizationId);
    await _seedTelemetry(organizationId);
  }

  Future<void> _seedVehicles(String organizationId) async {
    final vehicles = [
      {'plate': 'BRA-2026', 'model': 'Volvo FH 540', 'capacity': 40000},
      {'plate': 'VPR-0001', 'model': 'Scania R 450', 'capacity': 35000},
    ];

    for (var v in vehicles) {
      try {
        final exists = await _supabase
            .from('vehicles')
            .select()
            .eq('plate', v['plate']!)
            .maybeSingle();

        if (exists == null) {
          final payload = Map<String, dynamic>.from(v);
          payload['organization_id'] = organizationId;
          await _supabase.from('vehicles').insert(payload);
        }
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }
    }
  }

  Future<void> _seedTelemetry(String organizationId) async {
    Map<String, dynamic> vehicle;
    try {
      vehicle = await _supabase
          .from('vehicles')
          .select()
          .eq('organization_id', organizationId)
          .limit(1)
          .single();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
    }

    final now = _dateTimeProvider.nowUtc();
    final rawId = const Uuid().v4();

    try {
      await _supabase.from('raw_telemetry_payloads').insert({
        'id': rawId,
        'organization_id': organizationId,
        'provider_name': 'SASCAR',
        'device_id': 'DEV-${vehicle['plate']}',
        'raw_payload': {'simulated': true, 'batch': now.millisecondsSinceEpoch},
        'payload_hash': 'hash-${now.millisecondsSinceEpoch}',
      });
    } on PostgrestException catch (e) {
      if (e.code != '42501') {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }
    }

    final points = [
      {'lat': -23.5505, 'lng': -46.6333},
      {'lat': -23.5515, 'lng': -46.6343},
      {'lat': -23.5525, 'lng': -46.6353},
      {'lat': -23.5535, 'lng': -46.6363},
    ];

    for (int i = 0; i < points.length; i++) {
      try {
        await _supabase.from('canonical_facts').insert({
          'organization_id': organizationId,
          'raw_payload_id': rawId,
          'asset_id': vehicle['id'],
          'device_id': 'DEV-${vehicle['plate']}',
          'gps_timestamp': now
              .subtract(Duration(minutes: points.length - i))
              .toIso8601String(),
          'received_at_utc': now.toIso8601String(),
          'lat': points[i]['lat'],
          'lng': points[i]['lng'],
          'speed_cms': 8000,
          'source_adapter': 'SASCAR_V1',
          'integrity_flag': 'OK',
        });
      } on PostgrestException catch (e) {
        if (e.code != '42501') {
          throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
        }
      }
    }
  }

  @override
  Future<void> seedActiveSanctions(String organizationId) async {
    Map<String, dynamic>? contract;
    try {
      contract = await _supabase
          .from('contracts')
          .select()
          .eq('organization_id', organizationId)
          .limit(1)
          .maybeSingle();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
    }

    if (contract == null) return;

    final now = _dateTimeProvider.nowUtc();
    final setId = 'sim-set-${now.millisecondsSinceEpoch}';

    try {
      await _supabase.from('sla_audit_ledger_v2').insert({
        'organization_id': organizationId,
        'contract_id': contract['id'],
        'occurred_at_utc': now.toIso8601String(),
        'type': 'SANCTION_RECOMMENDED',
        'set_id': setId,
        'operator_id': 'system_seeder',
        'payload': {
          'rule_id': 'rule-speed-v1',
          'verdict_evidence': {
            'clause_ref': 'VEL-01',
            'rule_id': 'rule-speed-v1',
            'rule_version': 1,
            'primary_evidence_lat': -23.5505,
            'primary_evidence_lng': -46.6333,
            'primary_evidence_timestamp_utc': now.toIso8601String(),
            'evidence_hash':
                'seed000000000000000000000000000000000000000000000000000000000001',
            'delta_value': 8.5,
            'threshold_value': 80.0,
            'fine_cents': 150000,
            'confidence_score': 99,
          },
        },
      });
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
    }

    // Seed active operational alerts
    final alerts = [
      {
        'organization_id': organizationId,
        'entity_id': 'sim-alert-entity',
        'contract_id': contract['id'],
        'alert_type': 'NO_SHOW',
        'severity': 'CRITICAL',
        'status': 'ACTIVE',
        'triggered_at_utc': now
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'context': {
          'message':
              'Veículo planejado não compareceu ao ponto inicial dentro da janela de tolerância.',
        },
      },
      {
        'organization_id': organizationId,
        'entity_id': 'sim-alert-entity',
        'contract_id': contract['id'],
        'alert_type': 'DEVIATION',
        'severity': 'HIGH',
        'status': 'ACTIVE',
        'triggered_at_utc': now
            .subtract(const Duration(minutes: 15))
            .toIso8601String(),
        'context': {
          'message':
              'Desvio de rota crítica detectado no trecho da Rodovia dos Bandeirantes.',
        },
      },
      {
        'organization_id': organizationId,
        'entity_id': 'sim-alert-entity',
        'contract_id': contract['id'],
        'alert_type': 'EVIDENCE_GAP',
        'severity': 'WARNING',
        'status': 'ACTIVE',
        'triggered_at_utc': now
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
        'context': {
          'message': 'Ausência de pings de telemetria por mais de 5 minutos.',
        },
      },
      {
        'organization_id': organizationId,
        'entity_id': 'sim-alert-entity',
        'contract_id': contract['id'],
        'alert_type': 'TELEGRAM_ORPHAN',
        'severity': 'CRITICAL',
        'status': 'ACTIVE',
        'triggered_at_utc': now
            .subtract(const Duration(minutes: 45))
            .toIso8601String(),
        'context': {
          'message':
              'Evidência enviada via Telegram pendente de vinculação com viagem ativa.',
        },
      },
      {
        'organization_id': organizationId,
        'entity_id': 'sim-alert-entity',
        'contract_id': contract['id'],
        'alert_type': 'POTENTIAL_TIME_FRAUD',
        'severity': 'CRITICAL',
        'status': 'ACTIVE',
        'triggered_at_utc': now
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'context': {
          'message':
              'Suspeita de adulteração de relógio do dispositivo de telemetria.',
          'evidence_id': const Uuid().v4(),
        },
      },
    ];

    for (var alert in alerts) {
      try {
        final exists = await _supabase
            .from('operational_alerts')
            .select('id')
            .eq('organization_id', organizationId)
            .eq('alert_type', alert['alert_type']!)
            .eq('status', 'ACTIVE')
            .limit(1)
            .maybeSingle();
        if (exists == null) {
          await _supabase.from('operational_alerts').insert(alert);
        }
      } on PostgrestException catch (e) {
        if (e.code != '23505') {
          throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
        }
      }
    }
  }

  @override
  Future<void> seedPhase9(String organizationId) async {
    await _seedSmartCnpjContractors(organizationId);
    await _seedQuotaLimits(organizationId);
    await _seedHeartbeatAndLateArrivalScenarios(organizationId);
    await _seedJustifications(organizationId);
  }

  Future<void> _seedSmartCnpjContractors(String organizationId) async {
    final contractors = [
      {'name': 'Logística Ãguia S/A', 'cnpj': '61219049000196'},
      {'name': 'Transportes Veloz', 'cnpj': '11444777000161'},
    ];

    for (var c in contractors) {
      try {
        final exists = await _supabase
            .from('contractors')
            .select()
            .eq('tax_id', c['cnpj']!)
            .maybeSingle();
        if (exists == null) {
          final payload = {
            'organization_id': organizationId,
            'name': c['name'],
            'tax_id': c['cnpj'],
            'primary_email':
                'contact@${c['name'].toString().toLowerCase().replaceAll(RegExp(r'\s+'), '')}.com',
            'contact_name': 'Contato ${c['name']}',
          };
          await _supabase.from('contractors').insert(payload);
        }
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }
    }
  }

  Future<void> _seedQuotaLimits(String organizationId) async {
    for (int i = 0; i < 42; i++) {
      final plate = 'MOC-${1000 + i}';
      try {
        final exists = await _supabase
            .from('vehicles')
            .select()
            .eq('plate', plate)
            .maybeSingle();
        if (exists == null) {
          await _supabase.from('vehicles').insert({
            'organization_id': organizationId,
            'plate': plate,
            'model': 'Mockado $i',
            'capacity': 30000 + i,
          });
        }
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
      }
    }
  }

  Future<void> _seedHeartbeatAndLateArrivalScenarios(
    String organizationId,
  ) async {
    Map<String, dynamic>? vehicle;
    try {
      vehicle = await _supabase
          .from('vehicles')
          .select()
          .eq('organization_id', organizationId)
          .limit(1)
          .maybeSingle();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
    }

    if (vehicle == null) return;

    final vehicleId = vehicle['id'];
    final deviceId = "DEV-${vehicle['plate']}";
    final now = _dateTimeProvider.nowUtc();

    for (var fact in [
      {
        'raw_payload_id': const Uuid().v4(),
        'gps_timestamp': now
            .subtract(const Duration(hours: 25))
            .toIso8601String(),
        'received_at_utc': now
            .subtract(const Duration(hours: 25))
            .toIso8601String(),
        'lat': -23.51,
        'lng': -46.61,
        'speed_cms': 0,
      },
      {
        'raw_payload_id': const Uuid().v4(),
        'gps_timestamp': now
            .subtract(const Duration(hours: 40))
            .toIso8601String(),
        'received_at_utc': now.toIso8601String(),
        'lat': -23.52,
        'lng': -46.62,
        'speed_cms': 6000,
      },
      {
        'raw_payload_id': const Uuid().v4(),
        'gps_timestamp': now
            .subtract(const Duration(hours: 50))
            .toIso8601String(),
        'received_at_utc': now.toIso8601String(),
        'lat': -23.53,
        'lng': -46.63,
        'speed_cms': 7000,
      },
    ]) {
      try {
        await _supabase.from('canonical_facts').insert({
          'organization_id': organizationId,
          'raw_payload_id': fact['raw_payload_id'],
          'asset_id': vehicleId,
          'device_id': deviceId,
          'gps_timestamp': fact['gps_timestamp'],
          'received_at_utc': fact['received_at_utc'],
          'lat': fact['lat'],
          'lng': fact['lng'],
          'speed_cms': fact['speed_cms'],
          'source_adapter': 'SASCAR_V1',
          'integrity_flag': 'OK',
        });
      } on PostgrestException catch (e) {
        if (e.code != '42501') {
          throw mapPostgrestToDomainException(e, resourceType: 'data_seed');
        }
      }
    }
  }

  Future<void> _seedJustifications(String organizationId) async {
    Map<String, dynamic>? contract;
    try {
      contract = await _supabase
          .from('contracts')
          .select()
          .eq('organization_id', organizationId)
          .limit(1)
          .maybeSingle();
    } catch (_) {}

    if (contract == null) return;

    final now = _dateTimeProvider.nowUtc();
    final justifications = [
      {
        'organization_id': organizationId,
        'contract_id': contract['id'],
        'set_id': 'sim-set-justification-1',
        'category': 'TRAFFIC',
        'description':
            'Simulação de contingência: Veículo retido no trânsito da Marginal Tietê devido a acidente grave envolvendo caminhão.',
        'status': 'PENDING',
        'created_at_utc': now
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
      },
      {
        'organization_id': organizationId,
        'contract_id': contract['id'],
        'set_id': 'sim-set-justification-2',
        'category': 'MECHANICAL',
        'description':
            'Simulação de contingência: Quebra da embreagem do veículo no KM 120 da rodovia, necessitando acionamento de guincho.',
        'status': 'APPROVED',
        'created_at_utc': now
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'reviewed_by_user_id': '00000000-0000-0000-0000-ffffffffffff',
        'reviewed_at_utc': now
            .subtract(const Duration(hours: 12))
            .toIso8601String(),
        'resolution_notes': 'Aprovado pelo seeder automático.',
      },
      {
        'organization_id': organizationId,
        'contract_id': contract['id'],
        'set_id': 'sim-set-justification-3',
        'category': 'COMMUNICATION',
        'description':
            'Simulação de contingência: Problemas de sinal no rastreador Sascar impediram o envio de pings durante todo o trajeto.',
        'status': 'REJECTED',
        'created_at_utc': now
            .subtract(const Duration(days: 2))
            .toIso8601String(),
        'reviewed_by_user_id': '00000000-0000-0000-0000-ffffffffffff',
        'reviewed_at_utc': now
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'resolution_notes': 'Rejeitado pelo seeder automático.',
      },
    ];

    for (var j in justifications) {
      try {
        final exists = await _supabase
            .from('contractor_justifications')
            .select('id')
            .eq('organization_id', organizationId)
            .eq('set_id', j['set_id']!)
            .limit(1)
            .maybeSingle();
        if (exists == null) {
          await _supabase.from('contractor_justifications').insert(j);
        }
      } catch (_) {}
    }
  }
}
