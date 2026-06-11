import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/resolve_dispute_command.dart';
import 'package:veraprob/domain/enums/user_role.dart';

void main() {
  group('ResolveDisputeCommand (H6 contract)', () {
    test('carries the structured reason code and optional free text', () {
      const command = ResolveDisputeCommand(
        queueEntryId: 'entry-1',
        resolution: DisputeResolution.accept,
        resolvedByUserId: 'auditor-1',
        actorEmail: 'auditor@veraprob.com',
        resolutionReason: 'Force majeure proven.',
        reasonCode: 'FORCE_MAJEURE',
        callerRole: UserRole.auditor,
        organizationId: 'org-1',
        sessionId: 'session-1',
      );

      expect(command.reasonCode, 'FORCE_MAJEURE');
      expect(command.resolutionReason, 'Force majeure proven.');
    });

    test('evidenceIds defaults to an empty list', () {
      const command = ResolveDisputeCommand(
        queueEntryId: 'entry-1',
        resolution: DisputeResolution.overturn,
        resolvedByUserId: 'auditor-1',
        actorEmail: 'auditor@veraprob.com',
        reasonCode: 'SENSOR_FAULT',
        callerRole: UserRole.auditor,
        organizationId: 'org-1',
        sessionId: 'session-1',
      );

      expect(command.evidenceIds, isEmpty);
      expect(command.resolutionReason, isNull);
    });

    test('retract allows a null reason code and forwards evidence ids', () {
      const command = ResolveDisputeCommand(
        queueEntryId: 'entry-1',
        resolution: DisputeResolution.retract,
        resolvedByUserId: 'auditor-1',
        actorEmail: 'auditor@veraprob.com',
        reasonCode: null,
        evidenceIds: ['att-1', 'att-2'],
        callerRole: UserRole.auditor,
        organizationId: 'org-1',
        sessionId: 'session-1',
      );

      expect(command.reasonCode, isNull);
      expect(command.evidenceIds, ['att-1', 'att-2']);
      expect(command.resolution, DisputeResolution.retract);
    });
  });
}
