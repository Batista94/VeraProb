import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/infrastructure/sla_audit/supabase_fleet_health_query_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  final dynamic _mockResult;
  FakePostgrestFilterBuilder(this._mockResult);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) async {
    return onValue(_mockResult);
  }
}

void main() {
  group('SupabaseFleetHealthQueryService', () {
    late MockSupabaseClient mockClient;
    late SupabaseFleetHealthQueryService service;

    setUp(() {
      mockClient = MockSupabaseClient();
      service = SupabaseFleetHealthQueryService(mockClient);
    });

    test('should return empty view when RPC returns empty list', () async {
      when(
        () => mockClient.rpc<dynamic>(
          'get_fleet_health_status',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(<dynamic>[]));

      final result = await service.getFleetHealth(organizationId: 'org-123');

      expect(result.vehicles, isEmpty);
      expect(result.healthyCount, 0);
      expect(result.delayedCount, 0);
      expect(result.offlineCount, 0);
      expect(result.neverSeenCount, 0);
      expect(result.fleetActiveRatioBps, 0);
    });

    test(
      'should map RPC results and ensure UTC dates (INV-6) and counts',
      () async {
        final mockData = [
          {
            'vehicle_id': 'v-1',
            'plate': 'ABC-1234',
            'model': 'Truck A',
            'device_id': 'dev-1',
            'hardware_status': 'HEALTHY',
            'last_ping_utc': '2026-06-25T10:00:00Z',
            'gap_seconds': 10,
            'integrity_score_bps': 10000,
            'anomaly_count_24h': 0,
            'fleet_active_ratio': 0.75, // 75%
          },
          {
            'vehicle_id': 'v-2',
            'plate': 'XYZ-9876',
            'model': 'Truck B',
            'device_id': 'dev-2',
            'hardware_status': 'OFFLINE',
            'last_ping_utc': '2026-06-25T08:00:00Z',
            'gap_seconds': 7200,
            'integrity_score_bps': 8000,
            'anomaly_count_24h': 2,
            'fleet_active_ratio': 0.75, // duplicated per CROSS JOIN row
          },
        ];

        when(
          () => mockClient.rpc<dynamic>(
            'get_fleet_health_status',
            params: {
              'p_organization_id': 'org-123',
              'p_delayed_sec': 900,
              'p_offline_sec': 3600,
            },
          ),
        ).thenAnswer((_) => FakePostgrestFilterBuilder(mockData));

        final result = await service.getFleetHealth(organizationId: 'org-123');

        expect(result.vehicles.length, 2);
        expect(result.healthyCount, 1);
        expect(result.offlineCount, 1);
        expect(result.delayedCount, 0);
        expect(result.neverSeenCount, 0);
        expect(result.fleetActiveRatioBps, 7500);

        // Ensure it parsed to UTC for lastPingUtc
        expect(result.vehicles[0].lastPingUtc?.isUtc, isTrue);
        expect(result.vehicles[0].lastPingUtc, DateTime.utc(2026, 6, 25, 10));

        expect(result.vehicles[0].hardwareStatus, HardwareStatusView.healthy);
        expect(result.vehicles[1].hardwareStatus, HardwareStatusView.offline);
      },
    );
  });
}
