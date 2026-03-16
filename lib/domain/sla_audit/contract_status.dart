/// The lifecycle status of a [Contract] aggregate.
///
/// Transitions are controlled exclusively by the [Contract] domain methods.
/// External code may never assign a status directly.
///
/// State machine:
/// ```
///   create() → [draft] → submit() → [awaitingContractorAcceptance] → activate() → [active] 
///   ...or [draft] → activate() → [active] (admin override)
///   [active] → close() → [closed]
/// ```
/// [closed] is a terminal state — no transitions out.
enum ContractStatus {
  /// Contract created but no plan has been declared yet.
  draft,

  /// Contract has been defined and is waiting for the contractor to review and accept terms.
  awaitingContractorAcceptance,

  /// First plan has been declared or contractor accepted — contract is operational.
  active,

  /// Contract has been formally closed — accepts no new plans.
  closed,
}
