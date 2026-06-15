import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/acknowledge_sanction_internal_command.dart';
import 'package:veraprob/domain/enums/user_role.dart';

AcknowledgeSanctionInternalCommand _cmd({String? notes = 'ok'}) =>
    AcknowledgeSanctionInternalCommand(
      organizationId: 'org-1',
      queueEntryId: 'q-1',
      acknowledgedByUserId: 'u-1',
      callerRole: UserRole.admin,
      sessionId: 's-1',
      notes: notes,
    );

void main() {
  group('AcknowledgeSanctionInternalCommand', () {
    test('notes is optional (null by default-omission)', () {
      const c = AcknowledgeSanctionInternalCommand(
        organizationId: 'org-1',
        queueEntryId: 'q-1',
        acknowledgedByUserId: 'u-1',
        callerRole: UserRole.admin,
        sessionId: 's-1',
      );
      expect(c.notes, isNull);
    });

    test('value equality covers every field (incl. notes + role)', () {
      expect(_cmd(), _cmd());
      expect(_cmd(notes: 'a'), isNot(_cmd(notes: 'b')));
    });

    test('props expose the auth-relevant fields', () {
      final c = _cmd();
      expect(c.props, contains('org-1'));
      expect(c.props, contains(UserRole.admin));
      expect(c.props, contains('s-1'));
    });
  });
}
