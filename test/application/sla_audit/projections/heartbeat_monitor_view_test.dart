import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/heartbeat_monitor_view.dart';
import 'package:veraprob/domain/sla_audit/heartbeat_classification.dart';

DeviceHeartbeatStatus _device(
  String id,
  HeartbeatClassification classification,
) {
  return DeviceHeartbeatStatus(
    assetId: id,
    lastSeenAtUtc: DateTime.utc(2026, 1, 1),
    gapSeconds: classification == HeartbeatClassification.normal ? 30 : 120,
    classification: classification,
    fleetActiveRatio: 0.9,
  );
}

void main() {
  group('HeartbeatMonitorView', () {
    test('totalCount equals number of devices', () {
      final view = HeartbeatMonitorView(
        devices: [
          _device('a1', HeartbeatClassification.normal),
          _device('a2', HeartbeatClassification.deviceTamper),
          _device('a3', HeartbeatClassification.networkIssue),
        ],
        tamperCount: 1,
        networkIssueCount: 1,
        normalCount: 1,
        unknownCount: 0,
      );

      expect(view.totalCount, 3);
    });

    test('hasAlerts is true when tamperCount > 0', () {
      final view = HeartbeatMonitorView(
        devices: [_device('a1', HeartbeatClassification.deviceTamper)],
        tamperCount: 1,
        networkIssueCount: 0,
        normalCount: 0,
        unknownCount: 0,
      );

      expect(view.hasAlerts, isTrue);
    });

    test('hasAlerts is true when unknownCount > 0', () {
      final view = HeartbeatMonitorView(
        devices: [_device('a1', HeartbeatClassification.unknown)],
        tamperCount: 0,
        networkIssueCount: 0,
        normalCount: 0,
        unknownCount: 1,
      );

      expect(view.hasAlerts, isTrue);
    });

    test('hasAlerts is false when only normal and networkIssue', () {
      final view = HeartbeatMonitorView(
        devices: [
          _device('a1', HeartbeatClassification.normal),
          _device('a2', HeartbeatClassification.networkIssue),
        ],
        tamperCount: 0,
        networkIssueCount: 1,
        normalCount: 1,
        unknownCount: 0,
      );

      expect(view.hasAlerts, isFalse);
    });

    test('empty fleet has totalCount = 0 and no alerts', () {
      const view = HeartbeatMonitorView(
        devices: [],
        tamperCount: 0,
        networkIssueCount: 0,
        normalCount: 0,
        unknownCount: 0,
      );

      expect(view.totalCount, 0);
      expect(view.hasAlerts, isFalse);
    });

    test('equality is structural', () {
      final t = DateTime.utc(2026, 1, 1);
      final d = DeviceHeartbeatStatus(
        assetId: 'x',
        lastSeenAtUtc: t,
        gapSeconds: 10,
        classification: HeartbeatClassification.normal,
        fleetActiveRatio: 1.0,
      );

      final a = HeartbeatMonitorView(
        devices: [d],
        tamperCount: 0,
        networkIssueCount: 0,
        normalCount: 1,
        unknownCount: 0,
      );
      final b = HeartbeatMonitorView(
        devices: [d],
        tamperCount: 0,
        networkIssueCount: 0,
        normalCount: 1,
        unknownCount: 0,
      );

      expect(a, equals(b));
    });
  });
}
