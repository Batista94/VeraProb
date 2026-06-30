import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

const double _kPortalTitleFontSize = 16.0;

class PortalHeader extends StatelessWidget {
  final String orgDisplayName;
  final String orgCnpj;

  const PortalHeader({
    super.key,
    required this.orgDisplayName,
    required this.orgCnpj,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.shield_rounded,
              color: VeraProbColors.primary,
              size: 28,
            ),
            const SizedBox(width: VeraProbSpacing.sm),
            Text(
              'VeraProb · Portal Oficial de Resolução de Disputas',
              style: VeraProbTypography.sectionTitle.copyWith(
                fontSize: _kPortalTitleFontSize,
              ),
            ),
          ],
        ),
        const SizedBox(height: VeraProbSpacing.md),
        Text(
          'Emitido para: $orgDisplayName · CNPJ $orgCnpj',
          textAlign: TextAlign.center,
          style: VeraProbTypography.bodyMedium,
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline,
              color: VeraProbColors.success,
              size: 16,
            ),
            const SizedBox(width: VeraProbSpacing.xs),
            Text(
              'Conexão verificada · portal.veraprob.com',
              style: VeraProbTypography.caption.copyWith(
                color: VeraProbColors.success,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
