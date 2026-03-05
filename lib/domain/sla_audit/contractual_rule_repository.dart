import 'contractual_rule.dart';
import 'rule_snapshot.dart';

/// Repository interface for managing contractual rule configurations.
/// Supports fetching active rules for temporal snapshot generation.
abstract class ContractualRuleRepository {
  /// Fetches the currently active rules for a contract to generate an immutable snapshot.
  /// Throws an exception if critical rules are missing.
  Future<RuleSnapshot> getActiveSnapshotForContract(
    String organizationId,
    String contractId,
  );

  /// Saves a new rule configuration version or set.
  Future<void> saveRule(ContractualRule rule);
}
