/// The lifecycle status of a [Contract] aggregate.
///
/// Transitions are controlled exclusively by the [Contract] domain methods.
/// External code may never assign a status directly.
///
/// State machine:
/// ```
///   create() → [draft] → activate() → [active] → close() → [closed]
/// ```
/// [closed] is a terminal state — no transitions out.
enum ContractStatus {
  /// Contract created but no plan has been declared yet.
  draft,

  /// First plan has been declared — contract is operational.
  active,

  /// Contract has been formally closed — accepts no new plans.
  closed,
}
