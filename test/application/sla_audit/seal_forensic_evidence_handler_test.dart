import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/seal_forensic_evidence_command.dart';
import 'package:veraprob/application/sla_audit/seal_forensic_evidence_handler.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_forensic_evidence_snapshot_repository.dart';

class _MockAuth extends Mock implements IAuthRepository {}

void main() {
  late InMemoryForensicEvidenceSnapshotRepository vault;
  late SealForensicEvidenceHandler handler;
  late _MockAuth auth;

  final occurred = DateTime.utc(2026, 8, 1, 12);

  setUp(() {
    auth = _MockAuth();
    when(
      () => auth.getUserBySessionId(any<String>()),
    ).thenAnswer((_) async => const AuthUser(id: 'user-1', tenantId: 'org-1'));

    vault = InMemoryForensicEvidenceSnapshotRepository()
      ..seedRules(
        organizationId: 'org-1',
        contractId: 'contract-1',
        ruleSetId: 'rs-1',
        slaRuleVersion: 2,
        rules: [
          {
            'rule_id': 'rule-1',
            'rule_type': 'NO_SHOW_PENALTY',
            'rule_config': {'multiplier_value': 2},
            'rule_version': 2,
            'evaluation_order': 0,
          },
        ],
      );

    handler = SealForensicEvidenceHandler(
      tenantValidator: TenantValidationService(authRepository: auth),
      vault: vault,
    );
  });

  SealForensicEvidenceCommand command({
    String organizationId = 'org-1',
    String idempotencyKey = 'idem-1',
    DateTime? occurredAtUtc,
  }) => SealForensicEvidenceCommand(
    organizationId: organizationId,
    sessionId: 'session-1',
    contractId: 'contract-1',
    setId: 'set-1',
    verdictType: 'NO_SHOW_PENALTY',
    planVersion: 1,
    occurredAtUtc: occurredAtUtc ?? occurred,
    sealedBy: 'user-1',
    idempotencyKey: idempotencyKey,
  );

  test('seals a verdict and returns the snapshot', () async {
    final s = await handler.handle(command());
    expect(s.organizationId, 'org-1');
    expect(s.slaRuleVersion, 2);
    expect(vault.count, 1);
  });

  test(
    'replay with same idempotency key returns one snapshot (INV-11)',
    () async {
      final first = await handler.handle(command());
      final second = await handler.handle(command());
      expect(second.id, first.id);
      expect(vault.count, 1);
    },
  );

  test('rejects cross-tenant seal (INV-1 fail-fast)', () async {
    expect(
      () => handler.handle(command(organizationId: 'org-OTHER')),
      throwsA(isA<SovereigntyViolationException>()),
    );
    expect(vault.count, 0);
  });

  test('rejects a non-UTC verdict timestamp (INV-6)', () async {
    expect(
      () => handler.handle(command(occurredAtUtc: DateTime(2026, 8, 1, 9))),
      throwsA(isA<DomainException>()),
    );
  });
}
