import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_dispute_reason_code_repository.dart';

void main() {
  late InMemoryDisputeReasonCodeRepository repo;

  setUp(() => repo = InMemoryDisputeReasonCodeRepository());

  group('InMemoryDisputeReasonCodeRepository', () {
    test('returns the full seeded global catalogue, all active', () async {
      final codes = await repo.findAllActive();

      expect(codes, hasLength(16));
      expect(codes.every((c) => c.isActive), isTrue);
    });

    test('mirrors the migration seed (agnostic code + category)', () async {
      final codes = await repo.findAllActive();
      final third = codes.firstWhere((c) => c.code == 'THIRD_PARTY_INCIDENT');

      expect(third.category, 'OPERATIONAL');
      expect(third.labelPt, 'Incidente com Terceiro');
      expect(third.labelEn, 'Third-Party Incident');
    });

    test(
      'exposes the OTHER escape code (forces a free-text complement)',
      () async {
        final codes = await repo.findAllActive();

        expect(
          codes.any((c) => c.code == 'OTHER' && c.category == 'OTHER'),
          isTrue,
        );
      },
    );

    test(
      'organizationId is accepted but does not change the global result',
      () async {
        final global = await repo.findAllActive();
        final scoped = await repo.findAllActive(organizationId: 'org-1');

        expect(scoped, global);
      },
    );
  });
}
