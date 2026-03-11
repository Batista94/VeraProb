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
        'name': 'Cidade Universitária / Metrô Barra Funda',
        'agency_id': 'SPTRANS',
      },
      {
        'gtfs_route_id': '875C-10',
        'name': 'Term. Lapa / Metrô Santa Cruz',
        'agency_id': 'SPTRANS',
      },
      {
        'gtfs_route_id': '917H-10',
        'name': 'Term. Pirituba / Metrô Vila Mariana',
        'agency_id': 'SPTRANS',
      },
      {
        'gtfs_route_id': '701U-10',
        'name': 'Cidade Universitária / Metrô Santana',
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

  Future<void> clearAll() async {
    // DANGEROUS: Only for dev
    // await _supabase.from('vehicle_positions').delete().neq('id', 0);
    // await _supabase.from('trips_audit').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    // await _supabase.from('drivers').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    // await _supabase.from('routes').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  }
}
