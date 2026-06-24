import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/retire_contractual_rule_handler.dart';
import 'package:veraprob/application/sla_audit/rule_studio_command_service.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class _FakeCommandService implements RuleStudioCommandService {
  String? lastRetiredRuleId;

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
  }) async => 'scheduled-rule-uuid';

  @override
  Future<void> activateScheduledRule({required String ruleId}) async {}

  @override
  Future<void> retireRule({required String ruleId}) async {
    lastRetiredRuleId = ruleId;
  }
}

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockAuthRepo;
  late _FakeCommandService fakeService;
  late RetireContractualRuleHandler handler;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    fakeService = _FakeCommandService();
    handler = RetireContractualRuleHandler(
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

  RetireContractualRuleCommand cmd({UserRole role = UserRole.admin}) {
    return RetireContractualRuleCommand(
      organizationId: 'org-1',
      ruleId: 'rule-to-retire',
      callerRole: role,
      sessionId: 'session-1',
    );
  }

  group('RetireContractualRuleHandler', () {
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
      expect(fakeService.lastRetiredRuleId, isNull);
    });

    test('auditor role is denied', () async {
      expect(
        () => handler.handle(cmd(role: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
    });

    test('admin retires rule — rule id forwarded to the service', () async {
      await handler.handle(cmd());
      expect(fakeService.lastRetiredRuleId, 'rule-to-retire');
    });

    test('tenant mismatch is rejected before any command (INV-1)', () async {
      when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
        (_) async => const domain.AuthUser(
          id: 'user-2',
          email: 'intruder@test.com',
          tenantId: 'org-OTHER',
        ),
      );

      await expectLater(handler.handle(cmd()), throwsA(isA<Object>()));
      expect(fakeService.lastRetiredRuleId, isNull);
    });
  });
}
