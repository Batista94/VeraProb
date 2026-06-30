import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Shared surface container — the standard Industrial Dark panel chrome.
///
/// Extracts the repeated `Container(BoxDecoration(color:surface,
/// borderRadius:12, border:VeraProbColors.border))` so every panel is pixel-
/// identical without copy-pasted decoration parameters.
class PanelContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const PanelContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? VeraProbSpacing.sectionPadding,
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: child,
    );
  }
}
