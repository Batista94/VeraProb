import 'package:flutter/material.dart';

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

  Color get color {
    switch (this) {
      case IncidentLifecycleStatus.open:
        return const Color(0xFFFF1744); // Critical Red
      case IncidentLifecycleStatus.acknowledged:
        return const Color(0xFFFF9100); // Amber
      case IncidentLifecycleStatus.inProgress:
        return const Color(0xFF29B6F6); // Light Blue
      case IncidentLifecycleStatus.resolved:
        return const Color(0xFF00C853); // Success Green
    }
  }
}
