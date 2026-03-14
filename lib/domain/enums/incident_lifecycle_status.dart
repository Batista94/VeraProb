/// Represents the operational tracking phase of a critical incident.
/// Used in Audit Logs and Alert Sidebars designed for OCC density.
enum IncidentLifecycleStatus {
  open,
  acknowledged,
  inProgress,
  resolved;

  String get label {
    switch (this) {
      case IncidentLifecycleStatus.open:
        return 'ABERTO';
      case IncidentLifecycleStatus.acknowledged:
        return 'RECONHECIDO';
      case IncidentLifecycleStatus.inProgress:
        return 'EM ANDAMENTO';
      case IncidentLifecycleStatus.resolved:
        return 'RESOLVIDO';
    }
  }
}
