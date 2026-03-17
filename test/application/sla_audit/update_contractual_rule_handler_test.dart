import 'package:flutter_test/flutter_test.dart';
import 'package:pactaflow/application/sla_audit/rule_studio_command_service.dart';
import 'package:pactaflow/application/sla_audit/update_contractual_rule_command.dart';
import 'package:pactaflow/application/sla_audit/update_contractual_rule_handler.dart';
import 'package:pactaflow/domain/enums/user_role.dart';
import 'package:pactaflow/domain/services/rbac_service.dart';
import 'package:pactaflow/domain/sla_audit/contractual_rule.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';

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
  }) async {
    lastContractId = contractId;
    lastOldRuleId  = oldRuleId;
    lastRuleType   = ruleType;
    lastConfig     = newConfig;
    lastOrder      = evaluationOrder;
    return 'new-rule-uuid-1234';
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _FakeCommandService fakeService;
  late UpdateContractualRuleHandler handler;

  setUp(() {
    fakeService = _FakeCommandService();
    handler = UpdateContractualRuleHandler(
      commandService: fakeService,
      rbac: RbacService(),
    );
  });

  UpdateContractualRuleCommand _cmd({
    UserRole role = UserRole.admin,
    SlaRuleType ruleType = SlaRuleType.minGeofenceCoverage,
    Map<String, dynamic>? config,
    String? oldRuleId,
  }) {
    return UpdateContractualRuleCommand(
      organizationId:  'org-1',
      contractId:      'contract-1',
      oldRuleId:       oldRuleId,
      ruleType:        ruleType,
      newConfig:       config ?? {'min_dwell_seconds': 45},
      evaluationOrder: 1,
      callerRole:      role,
    );
  }

  group('UpdateContractualRuleHandler', () {
    // ── 7.1 + 7.3: RBAC ─────────────────────────────────────

    test('operator role is denied — canEditSlaRules is admin-only', () async {
      expect(
        () => handler.handle(_cmd(role: UserRole.operator)),
        throwsA(isA<DomainException>().having(
          (e) => e.message,
          'message',
          contains('canEditSlaRules'),
        )),
      );
    });

    test('auditor role is denied — canEditSlaRules is admin-only', () async {
      expect(
        () => handler.handle(_cmd(role: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
    });

    // ── 7.3: Successful version transition ───────────────────

    test('admin creates first version — returns new rule UUID', () async {
      final newId = await handler.handle(_cmd(oldRuleId: null));
      expect(newId, 'new-rule-uuid-1234');
      expect(fakeService.lastOldRuleId, isNull);
      expect(fakeService.lastRuleType, SlaRuleType.minGeofenceCoverage);
      expect(fakeService.lastConfig!['min_dwell_seconds'], 45);
    });

    test('admin updates existing version — passes oldRuleId to service', () async {
      final newId = await handler.handle(_cmd(oldRuleId: 'old-uuid'));
      expect(newId, 'new-rule-uuid-1234');
      expect(fakeService.lastOldRuleId, 'old-uuid');
    });

    // ── Config validation ─────────────────────────────────────

    test('MIN_GEOFENCE_COVERAGE with wrong key throws DomainException', () async {
      expect(
        () => handler.handle(_cmd(
          ruleType: SlaRuleType.minGeofenceCoverage,
          config: {'wrong_key': 30},
        )),
        throwsA(isA<DomainException>().having(
          (e) => e.message,
          'message',
          contains('min_dwell_seconds'),
        )),
      );
    });

    test('MAX_TOLERANCE_DELAY with correct key passes validation', () async {
      final newId = await handler.handle(_cmd(
        ruleType: SlaRuleType.maxToleranceDelay,
        config: {'threshold_minutes': 5},
      ));
      expect(newId, isNotEmpty);
    });

    test('NO_SHOW_PENALTY with correct key passes validation', () async {
      final newId = await handler.handle(_cmd(
        ruleType: SlaRuleType.noShowPenalty,
        config: {'penalty_amount_cents': 15000},
      ));
      expect(newId, isNotEmpty);
    });

    test('MAX_EVIDENCE_GAP with correct key passes validation', () async {
      final newId = await handler.handle(_cmd(
        ruleType: SlaRuleType.maxEvidenceGap,
        config: {'max_gap_seconds': 300},
      ));
      expect(newId, isNotEmpty);
    });
  });
}
