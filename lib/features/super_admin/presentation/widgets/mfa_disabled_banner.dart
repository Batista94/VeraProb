import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Banner warning that MFA is disabled in the current environment.
///
/// Visible **only** in debug and profile builds (`kDebugMode || kProfileMode`).
/// In release builds the widget renders nothing — the [child] is returned
/// directly without any wrapping.
///
/// When visible, a thin amber strip is rendered above [child] using
/// [VeraProbColors.warning] as background. The strip includes a hover
/// micro-interaction: elevation rises from 2 dp to 4 dp over 200 ms,
/// following the "Vivo" design-system pattern.
///
/// **INV-22:** Resides in `lib/features/super_admin/presentation/widgets/`.
class MfaDisabledBanner extends StatefulWidget {
  /// The content to display below the banner.
  final Widget child;

  const MfaDisabledBanner({super.key, required this.child});

  /// Whether the banner should be visible in the current build mode.
  ///
  /// Extracted as a static getter so tests can verify the logic without
  /// needing to change the build mode.
  static bool get isVisibleInCurrentMode => kDebugMode || kProfileMode;

  @override
  State<MfaDisabledBanner> createState() => _MfaDisabledBannerState();
}

class _MfaDisabledBannerState extends State<MfaDisabledBanner> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // In release builds, skip the banner entirely.
    if (!MfaDisabledBanner.isVisibleInCurrentMode) {
      return widget.child;
    }

    return Column(
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            decoration: BoxDecoration(
              color: VeraProbColors.warning,
              boxShadow: [
                BoxShadow(
                  color: const Color(0x33000000), // shadow
                  blurRadius: _isHovered ? 4 : 2,
                  offset: Offset(0, _isHovered ? 4 : 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(
              vertical: VeraProbSpacing.sm,
              horizontal: VeraProbSpacing.md,
            ),
            child: Text(
              '⚠ MFA desabilitado (ambiente de desenvolvimento)',
              textAlign: TextAlign.center,
              style: VeraProbTypography.bodySmall.copyWith(
                color: VeraProbColors.background,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
