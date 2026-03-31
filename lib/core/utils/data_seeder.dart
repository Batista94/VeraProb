import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class DataSeeder {
  final SupabaseClient _supabase;
  final String organizationId;

  DataSeeder(this._supabase, {required this.organizationId});

  Future<void> seedDrivers() async {
    // Check if drivers exist to avoid duplicates or clear them?
    // Let's just insert if not exists (using license_number as unique key)

    final drivers = [
      {'full_name': 'João Silva', 'license_number': '11122233344'},
      {'full_name': 'Maria Oliveira', 'license_number': '55566677788'},
      {'full_name': 'Carlos Santos', 'license_number': '99988877766'},
    ];

    for (var d in drivers) {
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
    }
  }

  Future<void> seedRoutes() async {
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
    }
  }

  Future<void> seedHistoricalData() async {
    // 1. Get or create a contract
    var contract = await _supabase
        .from('contracts')
        .select()
        .eq('organization_id', organizationId)
        .limit(1)
        .maybeSingle();

    if (contract == null) {
      final contractor = await _supabase
          .from('contractors')
          .select()
          .limit(1)
          .maybeSingle();

      final newContract = await _supabase
          .from('contracts')
          .insert({
            'organization_id': organizationId,
            'name': 'Contrato de Teste Histórico',
            'contractor_name': contractor?['name'] ?? 'Empresa Beta',
            'valid_from_utc': DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 30))
                .toIso8601String(),
            'valid_until_utc': DateTime.now()
                .toUtc()
                .add(const Duration(days: 30))
                .toIso8601String(),
            'status': 'active',
            'financial_ceiling_cents': 500000,
          })
          .select()
          .single();
      contract = newContract;
    }

    // 2. Clear previous historical test data to avoid pollution
    await _supabase
        .from('trips_audit')
        .delete()
        .eq('source_type', 'history_seed');

    // 3. Create trips for yesterday (16/03/2026)
    final yesterday = DateTime(2026, 03, 16);
    final routes = await _supabase
        .from('routes')
        .select('id')
        .eq('organization_id', organizationId)
        .limit(2);
    final drivers = await _supabase
        .from('drivers')
        .select('id')
        .eq('organization_id', organizationId)
        .limit(2);

    if (routes.isEmpty || drivers.isEmpty) return;

    final tripScenarios = [
      {'hour': 8, 'status': 'completed', 'penalty': 0},
      {
        'hour': 10,
        'status': 'completed',
        'penalty': 15000,
      }, // R$ 150,00 penalty
      {'hour': 14, 'status': 'completed', 'penalty': 0},
      {'hour': 16, 'status': 'completed', 'penalty': 5000}, // R$ 50,00 penalty
    ];

    for (var scenario in tripScenarios) {
      final startTime = yesterday.add(Duration(hours: scenario['hour'] as int));
      final endTime = startTime.add(const Duration(hours: 1));

      final trip = await _supabase
          .from('trips_audit')
          .insert({
            'organization_id': organizationId,
            'route_id': routes[0]['id'],
            'driver_id': drivers[0]['id'],
            'start_time': startTime.toIso8601String(),
            'end_time': endTime.toIso8601String(),
            'status': 'completed',
            'source_type': 'history_seed',
          })
          .select()
          .single();

      final tripId = trip['id'];

      // 4. Create Ledger Entries for these trips
      await _supabase.from('sla_audit_ledger_v2').insert({
        'organization_id': organizationId,
        'occurred_at_utc': endTime.toIso8601String(),
        'type': 'TRIP_VERDICT',
        'set_id': tripId,
        'operator_id': 'system_seeder',
        'new_value': scenario['penalty'] == 0 ? 'COMPLIANT' : 'NON_COMPLIANT',
        'payload': {'penalty_cents': scenario['penalty']},
      });
    }

    // 5. Create Financial Snapshot for the Dashboard using the real schema
    await _supabase.from('contractual_financial_snapshot').insert({
      'id': const Uuid().v4(),
      'organization_id': organizationId,
      'contract_id': contract['id'],
      'operational_date_utc': yesterday.toIso8601String().split('T').first,
      'operational_timezone': 'America/Sao_Paulo',
      'closed_at_utc': DateTime.now().toUtc().toIso8601String(),
      'total_contracted_revenue_cents': 40000,
      'protected_revenue_cents': 20000,
      'revenue_at_risk_cents': 0,
      'lost_revenue_cents': 20000,
      'risk_percentage': 0,
      'loss_percentage': 50.0,
      'total_obligations': 4,
      'executed_count': 4,
    });

    // 6. Seed some RAW Telemetry for the Map
    await seedVehicles();
    await seedTelemetry();
  }

  Future<void> seedVehicles() async {
    final vehicles = [
      {'plate': 'BRA-2026', 'model': 'Volvo FH 540', 'capacity': 40000},
      {'plate': 'VPR-0001', 'model': 'Scania R 450', 'capacity': 35000},
    ];

    for (var v in vehicles) {
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
    }
  }

  Future<void> seedTelemetry() async {
    // 1. Get a vehicle
    final vehicle = await _supabase
        .from('vehicles')
        .select()
        .eq('organization_id', organizationId)
        .limit(1)
        .single();

    final now = DateTime.now().toUtc();
    final rawId = const Uuid().v4();

    // 2. Create a Sealed Raw Payload
    await _supabase.from('raw_telemetry_payloads').insert({
      'id': rawId,
      'organization_id': organizationId,
      'provider_name': 'SASCAR',
      'device_id': 'DEV-${vehicle['plate']}',
      'raw_payload': {'simulated': true, 'batch': now.millisecondsSinceEpoch},
      'payload_hash': 'hash-${now.millisecondsSinceEpoch}',
    });

    // 3. Create a Breadcrumb (Route simulation near SP)
    final points = [
      {'lat': -23.5505, 'lng': -46.6333}, // Mark 0
      {'lat': -23.5515, 'lng': -46.6343}, // Mark 1
      {'lat': -23.5525, 'lng': -46.6353}, // Mark 2 (Infraction point maybe)
      {'lat': -23.5535, 'lng': -46.6363}, // Mark 3
    ];

    for (int i = 0; i < points.length; i++) {
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
        'speed_cms': 8000, // 80 km/h approx
        'source_adapter': 'SASCAR_V1',
        'integrity_flag': 'OK',
      });
    }
  }

  Future<void> seedActiveSanctions() async {
    // 1. Get or create a contract
    final contract = await _supabase
        .from('contracts')
        .select()
        .eq('organization_id', organizationId)
        .limit(1)
        .maybeSingle();

    if (contract == null) return;

    final now = DateTime.now().toUtc();
    final setId = 'sim-set-${now.millisecondsSinceEpoch}';

    // 2. Insert into Ledger (to maintain audit trail)
    // The DB trigger `tr_ledger_to_review_queue` will auto-populate the queue.
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
  }

  Future<void> clearAll() async {
    // DANGEROUS: Only for dev
    // await _supabase.from('vehicle_positions').delete().neq('id', 0);
    // await _supabase.from('trips_audit').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    // await _supabase.from('drivers').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    // await _supabase.from('routes').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  }

  // ── Phase 9 Scenarios (Resilience & Operational Hub) ────────────────────────
  Future<void> seedPhase9() async {
    await seedSmartCnpjContractors();
    await seedQuotaLimits();
    await seedHeartbeatAndLateArrivalScenarios();
  }

  Future<void> seedSmartCnpjContractors() async {
    final contractors = [
      {'name': 'Logística Águia S/A', 'cnpj': '61219049000196'},
      {'name': 'Transportes Veloz', 'cnpj': '11444777000161'},
    ];

    for (var c in contractors) {
      final exists = await _supabase
          .from('contractors')
          .select()
          .eq('cnpj', c['cnpj']!)
          .maybeSingle();
      if (exists == null) {
        final payload = Map<String, dynamic>.from(c);
        payload['organization_id'] = organizationId;
        payload['status'] = 'active';
        await _supabase.from('contractors').insert(payload);
      }
    }
  }

  Future<void> seedQuotaLimits() async {
    // Generate enough vehicles to reach > 80% of max_vehicles (default 50) => 42 vehicles
    // This turns the predictive quota indicator orange/red in the Dashboard
    for (int i = 0; i < 42; i++) {
      final plate = 'MOC-${1000 + i}';
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
    }
  }

  Future<void> seedHeartbeatAndLateArrivalScenarios() async {
    final vehicle = await _supabase
        .from('vehicles')
        .select()
        .eq('organization_id', organizationId)
        .limit(1)
        .maybeSingle();

    if (vehicle == null) return;

    final vehicleId = vehicle['id'];
    final deviceId = "DEV-${vehicle['plate']}";
    final now = DateTime.now().toUtc();

    // Heartbeat: Critical (Last 25 hours) - Tests 9.8.G
    await _supabase.from('canonical_facts').insert({
      'organization_id': organizationId,
      'raw_payload_id': const Uuid().v4(),
      'asset_id': vehicleId,
      'device_id': deviceId,
      'gps_timestamp': now
          .subtract(const Duration(hours: 25))
          .toIso8601String(),
      'received_at_utc': now
          .subtract(const Duration(hours: 25))
          .toIso8601String(),
      'lat': -23.51,
      'lng': -46.61,
      'speed_cms': 0,
      'source_adapter': 'SASCAR_V1',
      'integrity_flag': 'OK',
    });

    // Late-Arrival Valid (40h ago) - Tests 9.8.I In-window payload
    await _supabase.from('canonical_facts').insert({
      'organization_id': organizationId,
      'raw_payload_id': const Uuid().v4(),
      'asset_id': vehicleId,
      'device_id': deviceId,
      'gps_timestamp': now
          .subtract(const Duration(hours: 40))
          .toIso8601String(),
      'received_at_utc': now.toIso8601String(), // Arrived NOW
      'lat': -23.52, 'lng': -46.62, 'speed_cms': 6000,
      'source_adapter': 'SASCAR_V1', 'integrity_flag': 'OK',
    });

    // Late-Arrival Expired (50h ago) - Tests 9.8.I Out-of-window payload
    await _supabase.from('canonical_facts').insert({
      'organization_id': organizationId,
      'raw_payload_id': const Uuid().v4(),
      'asset_id': vehicleId,
      'device_id': deviceId,
      'gps_timestamp': now
          .subtract(const Duration(hours: 50))
          .toIso8601String(),
      'received_at_utc': now.toIso8601String(), // Arrived NOW
      'lat': -23.53, 'lng': -46.63, 'speed_cms': 7000,
      'source_adapter': 'SASCAR_V1', 'integrity_flag': 'OK',
    });
  }
}
