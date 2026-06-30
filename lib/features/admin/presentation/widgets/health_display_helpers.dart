import 'package:flutter/material.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';

abstract final class HealthDisplayHelpers {
  static Color colorForStatus(HardwareStatusView status) => switch (status) {
    HardwareStatusView.healthy => VeraProbColors.onTime,
    HardwareStatusView.delayed => VeraProbColors.delayed,
    HardwareStatusView.offline => VeraProbColors.critical,
    HardwareStatusView.neverSeen => VeraProbColors.neutral,
  };

  static Color colorForScore(int bps) {
    if (bps >= 7000) return VeraProbColors.onTime;
    if (bps >= 4000) return VeraProbColors.delayed;
    return VeraProbColors.critical;
  }

  static String formatGap(int seconds) {
    if (seconds >= 999999) return '—';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }
}
