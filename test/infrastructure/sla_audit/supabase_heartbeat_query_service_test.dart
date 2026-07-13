import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/sla_audit/heartbeat_classification.dart';
import 'package:veraprob/infrastructure/sla_audit/supabase_heartbeat_query_service.dart';

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
  group('SupabaseHeartbeatQueryService', () {
    late MockSupabaseClient mockClient;
    late SupabaseHeartbeatQueryService service;

    setUp(() {
      mockClient = MockSupabaseClient();
      service = SupabaseHeartbeatQueryService(mockClient);
    });

    test('empty RPC → zero counts (Availability / empty fleet)', () async {
      when(
        () => mockClient.rpc<dynamic>(
          'get_device_heartbeat_status',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(<dynamic>[]));

      final result = await service.getHeartbeatMonitor(organizationId: 'org-1');

      expect(result.devices, isEmpty);
      expect(result.tamperCount, 0);
      expect(result.networkIssueCount, 0);
      expect(result.normalCount, 0);
      expect(result.unknownCount, 0);
    });

    test(
      'passes organizationId to RPC (INV-1 Confidentiality — no client-derived org)',
      () async {
        when(
          () => mockClient.rpc<dynamic>(
            'get_device_heartbeat_status',
            params: {'p_organization_id': 'org-tenant-a'},
          ),
        ).thenAnswer((_) => FakePostgrestFilterBuilder(<dynamic>[]));

        await service.getHeartbeatMonitor(organizationId: 'org-tenant-a');

        verify(
          () => mockClient.rpc<dynamic>(
            'get_device_heartbeat_status',
            params: {'p_organization_id': 'org-tenant-a'},
          ),
        ).called(1);
      },
    );

    test('maps fleet_active_ratio 0.9 → 9000 BPS and classifies deviceTamper '
        '(Integrity — BPS conversion must not truncate ratio to 0)', () async {
      final mockData = [
        {
          'asset_id': 'asset-1',
          'last_seen_utc': '2026-06-25T10:00:00Z',
          'gap_seconds': 120,
          'fleet_active_ratio': 0.9,
        },
      ];

      when(
        () => mockClient.rpc<dynamic>(
          'get_device_heartbeat_status',
          params: {'p_organization_id': 'org-1'},
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(mockData));

      final result = await service.getHeartbeatMonitor(organizationId: 'org-1');

      expect(result.devices.single.fleetActiveBps, 9000);
      expect(
        result.devices.single.classification,
        HeartbeatClassification.deviceTamper,
      );
      expect(result.tamperCount, 1);
      expect(result.networkIssueCount, 0);
    });

    test(
      'fleet_active_ratio 0.2 + gap>90 → networkIssue (adversarial outage)',
      () async {
        final mockData = [
          {
            'asset_id': 'asset-2',
            'last_seen_utc': '2026-06-25T10:00:00Z',
            'gap_seconds': 200,
            'fleet_active_ratio': 0.2,
          },
        ];

        when(
          () => mockClient.rpc<dynamic>(
            'get_device_heartbeat_status',
            params: {'p_organization_id': 'org-1'},
          ),
        ).thenAnswer((_) => FakePostgrestFilterBuilder(mockData));

        final result = await service.getHeartbeatMonitor(
          organizationId: 'org-1',
        );

        expect(result.devices.single.fleetActiveBps, 2000);
        expect(
          result.devices.single.classification,
          HeartbeatClassification.networkIssue,
        );
        expect(result.networkIssueCount, 1);
      },
    );

    test('null fleet_active_ratio → 0 BPS (fail-closed)', () async {
      final mockData = [
        {
          'asset_id': 'asset-3',
          'last_seen_utc': '2026-06-25T10:00:00Z',
          'gap_seconds': 200,
          'fleet_active_ratio': null,
        },
      ];

      when(
        () => mockClient.rpc<dynamic>(
          'get_device_heartbeat_status',
          params: {'p_organization_id': 'org-1'},
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(mockData));

      final result = await service.getHeartbeatMonitor(organizationId: 'org-1');

      expect(result.devices.single.fleetActiveBps, 0);
      expect(
        result.devices.single.classification,
        HeartbeatClassification.networkIssue,
      );
    });

    test('lastSeenAtUtc is UTC (INV-6)', () async {
      final mockData = [
        {
          'asset_id': 'asset-4',
          'last_seen_utc': '2026-06-25T10:00:00Z',
          'gap_seconds': 10,
          'fleet_active_ratio': 1.0,
        },
      ];

      when(
        () => mockClient.rpc<dynamic>(
          'get_device_heartbeat_status',
          params: {'p_organization_id': 'org-1'},
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(mockData));

      final result = await service.getHeartbeatMonitor(organizationId: 'org-1');

      expect(result.devices.single.lastSeenAtUtc.isUtc, isTrue);
      expect(
        result.devices.single.classification,
        HeartbeatClassification.normal,
      );
      expect(result.normalCount, 1);
    });
  });
}
