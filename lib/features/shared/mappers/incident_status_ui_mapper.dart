import 'package:flutter/material.dart';

import 'package:veraprob/application/shared/app_types.dart';

/// Maps [IncidentLifecycleStatus] domain values to Flutter UI primitives.
/// Keeps the domain enum free of Flutter dependencies (DOMAIN SOVEREIGNTY invariant).
class IncidentStatusUiMapper {
  const IncidentStatusUiMapper._();

  static Color colorFor(IncidentLifecycleStatus status) {
    switch (status) {
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
