import 'package:supabase_flutter/supabase_flutter.dart';

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
      'organization_id': organizationId,
      'contract_id': contract['id'],
      'operational_date_utc': yesterday.toIso8601String().split('T').first,
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
  }

  Future<void> clearAll() async {
    // DANGEROUS: Only for dev
    // await _supabase.from('vehicle_positions').delete().neq('id', 0);
    // await _supabase.from('trips_audit').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    // await _supabase.from('drivers').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    // await _supabase.from('routes').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  }
}
