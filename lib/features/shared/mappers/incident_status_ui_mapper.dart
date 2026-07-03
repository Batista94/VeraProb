import 'package:flutter/material.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Maps [IncidentLifecycleStatus] domain values to Flutter UI primitives.
/// Keeps the domain enum free of Flutter dependencies (DOMAIN SOVEREIGNTY invariant).
class IncidentStatusUiMapper {
  const IncidentStatusUiMapper._();

  static Color colorFor(IncidentLifecycleStatus status) {
    switch (status) {
      case IncidentLifecycleStatus.open:
        return VeraProbColors.error;
      case IncidentLifecycleStatus.acknowledged:
        return VeraProbColors.warning;
      case IncidentLifecycleStatus.inProgress:
        return VeraProbColors.info;
      case IncidentLifecycleStatus.resolved:
        return VeraProbColors.success;
    }
  }
}
