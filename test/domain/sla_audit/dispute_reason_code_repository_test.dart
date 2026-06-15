import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code_repository.dart';

class _FakeReasonCodes implements DisputeReasonCodeRepository {
  String? lastOrg;
  bool orgArgPresent = false;

  @override
  Future<List<DisputeReasonCode>> findAllActive({
    String? organizationId,
  }) async {
    lastOrg = organizationId;
    orgArgPresent = true;
    return const [
      DisputeReasonCode(
        code: 'THIRD_PARTY_INCIDENT',
        category: 'EXTERNAL',
        labelPt: 'Incidente de terceiros',
        labelEn: 'Third-party incident',
        isActive: true,
      ),
    ];
  }
}

void main() {
  group('DisputeReasonCodeRepository (port contract)', () {
    test('findAllActive returns active codes; orgId is optional', () async {
      final repo = _FakeReasonCodes();
      final codes = await repo.findAllActive();
      expect(codes.single.code, 'THIRD_PARTY_INCIDENT');
      expect(repo.lastOrg, isNull);
    });

    test('forward-compatible orgId is threaded through', () async {
      final repo = _FakeReasonCodes();
      await repo.findAllActive(organizationId: 'org-1');
      expect(repo.lastOrg, 'org-1');
    });

    test('DisputeReasonCode identity is the code (VO)', () {
      const a = DisputeReasonCode(
        code: 'X',
        category: 'A',
        labelPt: 'a',
        labelEn: 'a',
        isActive: true,
      );
      const b = DisputeReasonCode(
        code: 'X',
        category: 'B',
        labelPt: 'b',
        labelEn: 'b',
        isActive: false,
      );
      expect(a, b); // equality on code only
    });
  });
}
