import 'dart:io';

void main() {
  final dir = Directory('test');
  if (!dir.existsSync()) return;

  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    var content = file.readAsStringSync();
    var original = content;

    // Inject imports if not present, but only if we match replacing
    bool requiresRuleSnapshot =
        content.contains('PlanDeclaration.create(') ||
        content.contains('PlanDeclaration.reconstitute(');
    bool requiresRuleRepo = content.contains('DeclareContractualPlanHandler(');

    if (requiresRuleSnapshot && !content.contains('rule_snapshot.dart')) {
      content =
          "import 'package:busflow/domain/sla_audit/rule_snapshot.dart';\n" +
          "import 'package:busflow/domain/sla_audit/contractual_rule.dart';\n" +
          content;
    }

    if (requiresRuleRepo &&
        !content.contains('contractual_rule_repository.dart')) {
      content =
          "import 'package:busflow/domain/sla_audit/contractual_rule_repository.dart';\n" +
          content;
    }

    content = content.replaceAll(
      "PlanDeclaration.create(organizationId: 'org-1', ",
      "PlanDeclaration.create(ruleSnapshot: const RuleSnapshot([]), organizationId: 'org-1', ",
    );
    content = content.replaceAll(
      "PlanDeclaration.reconstitute(organizationId: 'org-1', ",
      "PlanDeclaration.reconstitute(ruleSnapshot: const RuleSnapshot([]), organizationId: 'org-1', ",
    );

    // For cases where organizationId wasn't previously injected exactly like that
    content = content.replaceAll(
      'PlanDeclaration.create(\n',
      "PlanDeclaration.create(\n      ruleSnapshot: const RuleSnapshot([]),\n",
    );
    content = content.replaceAll(
      'PlanDeclaration.reconstitute(\n',
      "PlanDeclaration.reconstitute(\n      ruleSnapshot: const RuleSnapshot([]),\n",
    );

    // Mock RuleRepo for Handler
    if (content.contains('repository: planRepo') && requiresRuleRepo) {
      if (!content.contains('class MockContractualRuleRepository')) {
        content += '''
class MockContractualRuleRepository implements ContractualRuleRepository {
  @override
  Future<RuleSnapshot> getActiveSnapshotForContract(String orgId, String contractId) async {
    return const RuleSnapshot([]);
  }
  @override
  Future<void> saveRule(ContractualRule rule) async {}
}
''';
      }
      content = content.replaceAll(
        'repository: planRepo,',
        'repository: planRepo, ruleRepository: MockContractualRuleRepository(),',
      );
    }

    if (content != original) {
      file.writeAsStringSync(content);
      print('Updated \${file.path}');
    }
  }
}
