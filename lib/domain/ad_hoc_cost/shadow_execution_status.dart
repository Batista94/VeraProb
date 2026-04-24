/// Lifecycle status of a shadow execution cost object.
///
/// Shadow executions are created when evidence arrives with no linked contract.
/// They accumulate cost data until reconciled by a supervisor.
///
/// Transitions:
/// ```
/// UNLINKED_SHADOW → RECONCILED                (supervisor links to existing execution)
/// UNLINKED_SHADOW → RECONCILED_AS_NEW_REVENUE (supervisor promotes to new ad-hoc execution)
/// UNLINKED_SHADOW → DISMISSED                 (supervisor confirms non-billable event)
/// ```
/// RECONCILED, RECONCILED_AS_NEW_REVENUE, and DISMISSED are terminal (INV-3 guard in DB trigger).
enum ShadowExecutionStatus {
  /// Cost object created. Awaiting supervisor reconciliation.
  unlinkedShadow,

  /// Linked to an existing execution by a supervisor. Terminal.
  reconciled,

  /// No matching planned execution found → ad-hoc billing row created. Terminal.
  reconciledAsNewRevenue,

  /// Confirmed as non-billable by supervisor. Terminal.
  dismissed,
}

extension ShadowExecutionStatusX on ShadowExecutionStatus {
  String get dbValue => switch (this) {
    ShadowExecutionStatus.unlinkedShadow => 'UNLINKED_SHADOW',
    ShadowExecutionStatus.reconciled => 'RECONCILED',
    ShadowExecutionStatus.reconciledAsNewRevenue => 'RECONCILED_AS_NEW_REVENUE',
    ShadowExecutionStatus.dismissed => 'DISMISSED',
  };

  static ShadowExecutionStatus fromDb(String value) => switch (value) {
    'UNLINKED_SHADOW' => ShadowExecutionStatus.unlinkedShadow,
    'RECONCILED' => ShadowExecutionStatus.reconciled,
    'RECONCILED_AS_NEW_REVENUE' => ShadowExecutionStatus.reconciledAsNewRevenue,
    'DISMISSED' => ShadowExecutionStatus.dismissed,
    _ => throw ArgumentError('Unknown ShadowExecutionStatus: $value'),
  };
}
