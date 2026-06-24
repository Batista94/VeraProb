import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/dispute_reason_code_providers.dart';

class _FakeRepo implements DisputeReasonCodeRepository {
  String? lastOrg;
  @override
  Future<List<DisputeReasonCode>> findAllActive({
    String? organizationId,
  }) async {
    lastOrg = organizationId;
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
  test(
    'disputeReasonCodesProvider returns the catalogue and threads org id',
    () async {
      final fake = _FakeRepo();
      final c = ProviderContainer(
        overrides: [
          currentOrganizationIdProvider.overrideWithValue('org-1'),
          disputeReasonCodeRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(c.dispose);

      final codes = await c.read(disputeReasonCodesProvider.future);
      expect(codes.single.code, 'THIRD_PARTY_INCIDENT');
      expect(fake.lastOrg, 'org-1');
    },
  );
}
