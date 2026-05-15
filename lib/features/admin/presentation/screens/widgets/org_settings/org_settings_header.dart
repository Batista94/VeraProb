import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';

/// Section title + descriptive subtitle for the Organization Settings screen.
///
/// Pure presentation, no state — extracted from `_OrgSettingsScreenState` to
/// keep the screen file under the Presentation Complexity Gate (INV-13).
class OrgSettingsHeader extends StatelessWidget {
  const OrgSettingsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.business_outlined,
              size: 28,
              color: VeraProbColors.primary,
            ),
            const SizedBox(width: 12),
            Text(
              'Configurações da Organização',
              style: VeraProbTypography.sectionTitle,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Gerencie o perfil público, fuso horário, moeda e parâmetros operacionais da sua empresa.',
          style: VeraProbTypography.bodyMedium.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
