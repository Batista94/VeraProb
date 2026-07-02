// master_detail_scaffold.dart
//
// Responsive master-detail layout primitive.
//
// Wide (> VeraProbBreakpoints.medium): master + VerticalDivider + expanded detail.
// Narrow + hasSelection=false: only master visible.
// Narrow + hasSelection=true: only detail visible with a back button.
//
// Ponytail: no Scaffold — consumes parent shell Scaffold.
// This file is the SSOT for split/stack webhook layout. P5/P6 will migrate
// ingestion-health and super-admin tenants to this widget.

import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Generic responsive master-detail widget.
///
/// - Wide (> [VeraProbBreakpoints.medium]): renders [masterBuilder] and
///   [detailBuilder] side-by-side, separated by a [VerticalDivider].
/// - Narrow + [hasSelection] false: renders only [masterBuilder].
/// - Narrow + [hasSelection] true: renders a back button (key:
///   `'master-detail-back'`) above [detailBuilder]. Tapping it calls [onBack].
///
/// Master column width: `clamp(masterMinWidth, masterMaxWidth, maxWidth * 0.35)`.
class MasterDetailScaffold extends StatelessWidget {
  const MasterDetailScaffold({
    super.key,
    required this.masterBuilder,
    required this.detailBuilder,
    required this.hasSelection,
    required this.onBack,
    this.masterMinWidth = 320,
    this.masterMaxWidth = 400,
  });

  final WidgetBuilder masterBuilder;
  final WidgetBuilder detailBuilder;
  final bool hasSelection;
  final VoidCallback onBack;
  final double masterMinWidth;
  final double masterMaxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > VeraProbBreakpoints.medium;
        if (isWide) {
          return _buildWide(context, constraints.maxWidth);
        }
        return _buildNarrow(context);
      },
    );
  }

  Widget _buildWide(BuildContext context, double totalWidth) {
    final masterWidth = (totalWidth * 0.35).clamp(
      masterMinWidth,
      masterMaxWidth,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: masterWidth, child: masterBuilder(context)),
        const VerticalDivider(width: 1),
        Expanded(child: detailBuilder(context)),
      ],
    );
  }

  Widget _buildNarrow(BuildContext context) {
    if (!hasSelection) {
      return masterBuilder(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('master-detail-back'),
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Voltar'),
          ),
        ),
        Expanded(child: detailBuilder(context)),
      ],
    );
  }
}
