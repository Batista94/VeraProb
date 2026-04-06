import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule_repository.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';

/// In-memory stub of [ContractualRuleRepository].
///
/// Returns an empty [RuleSnapshot] (no rules configured).
/// Used in simulation/inMemory mode where rule configuration
/// is not yet needed. Phase 6 will add the Rule Configuration Studio.
class InMemoryContractualRuleRepository implements ContractualRuleRepository {
  @override
  Future<RuleSnapshot> getActiveSnapshotForContract(
    String organizationId,
    String contractId,
  ) async {
    return const RuleSnapshot([]);
  }

  @override
  Future<void> saveRule(ContractualRule rule) async {}
}
