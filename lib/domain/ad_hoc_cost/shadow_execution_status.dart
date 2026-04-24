/// Lifecycle status of a shadow execution cost object.
///
/// Shadow executions are created when evidence arrives with no linked contract.
/// They accumulate cost data until reconciled by a supervisor.
///
/// Transitions:
/// ```
/// UNLINKED_SHADOW → RECONCILED  (supervisor links to existing execution)
/// UNLINKED_SHADOW → DISMISSED   (supervisor confirms non-billable event)
/// ```
/// RECONCILED and DISMISSED are terminal (INV-3 guard in DB trigger).
enum ShadowExecutionStatus {
  /// Cost object created. Awaiting supervisor reconciliation.
  unlinkedShadow,

  /// Linked to an existing execution by a supervisor. Terminal.
  reconciled,

  /// Confirmed as non-billable by supervisor. Terminal.
  dismissed,
}

extension ShadowExecutionStatusX on ShadowExecutionStatus {
  String get dbValue => switch (this) {
    ShadowExecutionStatus.unlinkedShadow => 'UNLINKED_SHADOW',
    ShadowExecutionStatus.reconciled => 'RECONCILED',
    ShadowExecutionStatus.dismissed => 'DISMISSED',
  };

  static ShadowExecutionStatus fromDb(String value) => switch (value) {
    'UNLINKED_SHADOW' => ShadowExecutionStatus.unlinkedShadow,
    'RECONCILED' => ShadowExecutionStatus.reconciled,
    'DISMISSED' => ShadowExecutionStatus.dismissed,
    _ => throw ArgumentError('Unknown ShadowExecutionStatus: $value'),
  };
}
