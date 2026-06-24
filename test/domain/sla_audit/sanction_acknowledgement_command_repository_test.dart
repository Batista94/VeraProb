import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_acknowledgement_command_repository.dart';

class _FakeAck implements SanctionAcknowledgementCommandRepository {
  final bool reject;
  Map<String, Object?>? lastCall;
  _FakeAck({this.reject = false});

  @override
  Future<String> acknowledgeInternal({
    required String organizationId,
    required String queueEntryId,
    required String acknowledgedByUserId,
    String? notes,
  }) async {
    lastCall = {
      'organizationId': organizationId,
      'queueEntryId': queueEntryId,
      'acknowledgedByUserId': acknowledgedByUserId,
      'notes': notes,
    };
    if (reject) throw const DomainException('Acknowledgement rejected.');
    return 'ack-1';
  }
}

void main() {
  group('SanctionAcknowledgementCommandRepository (port contract)', () {
    test('acknowledgeInternal returns the new acknowledgement id', () async {
      final repo = _FakeAck();
      final id = await repo.acknowledgeInternal(
        organizationId: 'org-1',
        queueEntryId: 'q-1',
        acknowledgedByUserId: 'u-1',
        notes: 'phone',
      );
      expect(id, 'ack-1');
      expect(repo.lastCall!['notes'], 'phone');
    });

    test(
      'non-applied / insufficient authority surfaces an opaque domain error',
      () {
        final repo = _FakeAck(reject: true);
        expect(
          () => repo.acknowledgeInternal(
            organizationId: 'org-1',
            queueEntryId: 'q-1',
            acknowledgedByUserId: 'u-1',
          ),
          throwsA(isA<DomainException>()),
        );
      },
    );
  });
}
