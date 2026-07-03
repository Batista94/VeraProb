import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/super_admin/proxy_resilience_notifier.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Wraps [child] with a visual desaturation filter and "Stale Data" badge
/// when the proxy is in degraded/unavailable state.
///
/// INV-10: Integrity indicator — user knows data may not be fresh.
class StaleDataIndicator extends ConsumerWidget {
  final Widget child;
  const StaleDataIndicator({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStale = ref.watch(proxyResilienceProvider.select((s) => s.isStale));

    if (!isStale) return child;

    return Stack(
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.8, 0.1, 0.1, 0, 0, //
            0.1, 0.8, 0.1, 0, 0, //
            0.1, 0.1, 0.8, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
          child: child,
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: VeraProbColors.warning.withValues(alpha: 0.9),
              borderRadius: VeraProbRadii.smAll,
            ),
            // ACCENT-FILL-CONTRAST: dark foreground on warning fill.
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 12, color: VeraProbColors.background),
                SizedBox(width: 4),
                Text(
                  'STALE DATA',
                  style: TextStyle(
                    color: VeraProbColors.background,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
