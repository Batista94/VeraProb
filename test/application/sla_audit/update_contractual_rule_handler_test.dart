import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/rule_studio_command_service.dart';
import 'package:veraprob/application/sla_audit/update_contractual_rule_command.dart';
import 'package:veraprob/application/sla_audit/update_contractual_rule_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

// ── Fake command service ─────────────────────────────────────────────────────

class _FakeCommandService implements RuleStudioCommandService {
  String? lastContractId;
  String? lastOldRuleId;
  SlaRuleType? lastRuleType;
  Map<String, dynamic>? lastConfig;
  int? lastOrder;

  @override
  Future<String> updateRule({
    required String contractId,
    required String? oldRuleId,
    required SlaRuleType ruleType,
    required Map<String, dynamic> newConfig,
    required int evaluationOrder,
    required DateTime effectiveAtUtc,
  }) async {
    lastContractId = contractId;
    lastOldRuleId = oldRuleId;
    lastRuleType = ruleType;
    lastConfig = newConfig;
    lastOrder = evaluationOrder;
    return 'new-rule-uuid-1234';
  }

  @override
  Future<String> scheduleRule({
    required String contractId,
    required String? oldRuleId,
    required SlaRuleType ruleType,
    required Map<String, dynamic> newConfig,
    required int evaluationOrder,
    required DateTime effectiveAtUtc,
  }) async => 'scheduled-rule-uuid';

  @override
  Future<void> activateScheduledRule({required String ruleId}) async {}

  @override
  Future<void> retireRule({required String ruleId}) async {}
}

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;
  late _FakeCommandService fakeService;
  late UpdateContractualRuleHandler handler;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    fakeService = _FakeCommandService();
    handler = UpdateContractualRuleHandler(
      tenantValidator: tenantValidator,
      commandService: fakeService,
      rbac: RbacService(),
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  UpdateContractualRuleCommand cmd({
    UserRole role = UserRole.admin,
    SlaRuleType ruleType = SlaRuleType.minGeofenceCoverage,
    Map<String, dynamic>? config,
    String? oldRuleId,
  }) {
    return UpdateContractualRuleCommand(
      organizationId: 'org-1',
      contractId: 'contract-1',
      oldRuleId: oldRuleId,
      ruleType: ruleType,
      newConfig: config ?? {'min_dwell_seconds': 45},
      evaluationOrder: 1,
      callerRole: role,
      sessionId: 'session-1',
      effectiveAtUtc: DateTime.now().toUtc(),
    );
  }

  group('UpdateContractualRuleHandler', () {
    // ── 7.1 + 7.3: RBAC ─────────────────────────────────────

    test('operator role is denied — canEditSlaRules is admin-only', () async {
      expect(
        () => handler.handle(cmd(role: UserRole.operator)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('canEditSlaRules'),
          ),
        ),
      );
    });

    test('auditor role is denied — canEditSlaRules is admin-only', () async {
      expect(
        () => handler.handle(cmd(role: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
    });

    // ── 7.3: Successful version transition ───────────────────

    test('admin creates first version — returns new rule UUID', () async {
      final newId = await handler.handle(cmd(oldRuleId: null));
      expect(newId, 'new-rule-uuid-1234');
      expect(fakeService.lastOldRuleId, isNull);
      expect(fakeService.lastRuleType, SlaRuleType.minGeofenceCoverage);
      expect(fakeService.lastConfig!['min_dwell_seconds'], 45);
    });

    test(
      'admin updates existing version — passes oldRuleId to service',
      () async {
        final newId = await handler.handle(cmd(oldRuleId: 'old-uuid'));
        expect(newId, 'new-rule-uuid-1234');
        expect(fakeService.lastOldRuleId, 'old-uuid');
      },
    );

    // ── Config validation ─────────────────────────────────────

    test(
      'MIN_GEOFENCE_COVERAGE with wrong key throws DomainException',
      () async {
        expect(
          () => handler.handle(
            cmd(
              ruleType: SlaRuleType.minGeofenceCoverage,
              config: {'wrong_key': 30},
            ),
          ),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('min_dwell_seconds'),
            ),
          ),
        );
      },
    );

    test('MAX_TOLERANCE_DELAY with correct key passes validation', () async {
      final newId = await handler.handle(
        cmd(
          ruleType: SlaRuleType.maxToleranceDelay,
          config: {'threshold_minutes': 5},
        ),
      );
      expect(newId, isNotEmpty);
    });

    test('NO_SHOW_PENALTY with correct key passes validation', () async {
      final newId = await handler.handle(
        cmd(
          ruleType: SlaRuleType.noShowPenalty,
          config: {'penalty_amount_cents': 15000},
        ),
      );
      expect(newId, isNotEmpty);
    });

    test('MAX_EVIDENCE_GAP with correct key passes validation', () async {
      final newId = await handler.handle(
        cmd(
          ruleType: SlaRuleType.maxEvidenceGap,
          config: {'max_gap_seconds': 300},
        ),
      );
      expect(newId, isNotEmpty);
    });
  });
}
