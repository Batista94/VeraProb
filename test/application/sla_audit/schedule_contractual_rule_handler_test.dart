import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/rule_studio_command_service.dart';
import 'package:veraprob/application/sla_audit/schedule_contractual_rule_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class _FakeCommandService implements RuleStudioCommandService {
  String? lastContractId;
  String? lastOldRuleId;
  SlaRuleType? lastRuleType;
  Map<String, dynamic>? lastConfig;
  DateTime? lastEffectiveAtUtc;

  @override
  Future<String> updateRule({
    required String contractId,
    required String? oldRuleId,
    required SlaRuleType ruleType,
    required Map<String, dynamic> newConfig,
    required int evaluationOrder,
    required DateTime effectiveAtUtc,
  }) async => 'updated-rule-uuid';

  @override
  Future<String> scheduleRule({
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
    lastEffectiveAtUtc = effectiveAtUtc;
    return 'scheduled-rule-uuid-1234';
  }

  @override
  Future<void> activateScheduledRule({required String ruleId}) async {}

  @override
  Future<void> retireRule({required String ruleId}) async {}
}

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockAuthRepo;
  late _FakeCommandService fakeService;
  late ScheduleContractualRuleHandler handler;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    fakeService = _FakeCommandService();
    handler = ScheduleContractualRuleHandler(
      tenantValidator: TenantValidationService(authRepository: mockAuthRepo),
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

  ScheduleContractualRuleCommand cmd({
    UserRole role = UserRole.admin,
    SlaRuleType ruleType = SlaRuleType.maxToleranceDelay,
    Map<String, dynamic>? config,
    String? oldRuleId,
    DateTime? effectiveAtUtc,
  }) {
    return ScheduleContractualRuleCommand(
      organizationId: 'org-1',
      contractId: 'contract-1',
      oldRuleId: oldRuleId,
      ruleType: ruleType,
      newConfig: config ?? {'threshold_minutes': 20},
      evaluationOrder: 1,
      callerRole: role,
      sessionId: 'session-1',
      effectiveAtUtc:
          effectiveAtUtc ?? DateTime.now().toUtc().add(const Duration(days: 7)),
    );
  }

  group('ScheduleContractualRuleHandler', () {
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

    test('admin schedules future rule — returns scheduled UUID', () async {
      final effective = DateTime.now().toUtc().add(const Duration(days: 7));
      final newId = await handler.handle(cmd(effectiveAtUtc: effective));

      expect(newId, 'scheduled-rule-uuid-1234');
      expect(fakeService.lastContractId, 'contract-1');
      expect(fakeService.lastRuleType, SlaRuleType.maxToleranceDelay);
      expect(fakeService.lastEffectiveAtUtc, effective);
    });

    test('superseded rule id is forwarded to the service', () async {
      await handler.handle(cmd(oldRuleId: 'old-rule-uuid'));
      expect(fakeService.lastOldRuleId, 'old-rule-uuid');
    });

    test('config missing required key throws DomainException', () async {
      expect(
        () => handler.handle(
          cmd(ruleType: SlaRuleType.maxEvidenceGap, config: {'wrong_key': 1}),
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('max_gap_seconds'),
          ),
        ),
      );
    });

    test('config with correct key per type passes validation', () async {
      final newId = await handler.handle(
        cmd(
          ruleType: SlaRuleType.noShowPenalty,
          config: {'penalty_amount_cents': 25000},
        ),
      );
      expect(newId, isNotEmpty);
      expect(fakeService.lastConfig!['penalty_amount_cents'], 25000);
    });
  });
}
