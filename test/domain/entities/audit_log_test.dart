import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/audit_log.dart';

void main() {
  group('AuditLog', () {
    final DateTime ts = DateTime.utc(2026, 3, 25, 10, 0, 0);

    AuditLog buildLog({
      String id = 'log-001',
      String organizationId = 'org-1',
      String operatorId = 'user-abc',
      String actionType = 'TRIP_STATUS_CHANGE',
      String entityId = 'trip-xyz',
      String? oldValue = 'enRoute',
      String? newValue = 'completed',
      String? reason = 'Manual override',
      DateTime? timestamp,
    }) =>
        AuditLog(
          id: id,
          organizationId: organizationId,
          operatorId: operatorId,
          actionType: actionType,
          entityId: entityId,
          oldValue: oldValue,
          newValue: newValue,
          reason: reason,
          timestamp: timestamp ?? ts,
        );

    test('fromJson parses all fields', () {
      final json = {
        'id': 'log-123',
        'organization_id': 'org-abc',
        'operator_id': 'user-xyz',
        'action_type': 'DEVICE_OFFLINE',
        'entity_id': 'device-001',
        'old_value': 'online',
        'new_value': 'offline',
        'reason': 'Connectivity lost',
        'timestamp': ts.toIso8601String(),
      };
      final log = AuditLog.fromJson(json);
      expect(log.id, 'log-123');
      expect(log.organizationId, 'org-abc');
      expect(log.operatorId, 'user-xyz');
      expect(log.actionType, 'DEVICE_OFFLINE');
      expect(log.entityId, 'device-001');
      expect(log.oldValue, 'online');
      expect(log.newValue, 'offline');
      expect(log.reason, 'Connectivity lost');
      expect(log.timestamp, ts);
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'id': 'log-null',
        'organization_id': 'org-x',
        'operator_id': 'user-x',
        'action_type': 'ACTION',
        'entity_id': 'entity-x',
        'old_value': null,
        'new_value': null,
        'reason': null,
        'timestamp': ts.toIso8601String(),
      };
      final log = AuditLog.fromJson(json);
      expect(log.oldValue, isNull);
      expect(log.newValue, isNull);
      expect(log.reason, isNull);
    });

    test('toJson serializes all fields', () {
      final log = buildLog();
      final json = log.toJson();
      expect(json['id'], 'log-001');
      expect(json['organization_id'], 'org-1');
      expect(json['operator_id'], 'user-abc');
      expect(json['action_type'], 'TRIP_STATUS_CHANGE');
      expect(json['entity_id'], 'trip-xyz');
      expect(json['old_value'], 'enRoute');
      expect(json['new_value'], 'completed');
      expect(json['reason'], 'Manual override');
      expect(json['timestamp'], ts.toIso8601String());
    });

    test('equality is based on props', () {
      final l1 = buildLog();
      final l2 = buildLog();
      expect(l1, equals(l2));
    });

    test('props differ when actionType differs', () {
      final l1 = buildLog(actionType: 'A');
      final l2 = buildLog(actionType: 'B');
      expect(l1, isNot(equals(l2)));
    });
  });
}
