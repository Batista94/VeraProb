import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Generic 404 page for the SuperAdmin module.
///
/// Visually identical to a standard "Page Not Found" screen — it must NOT
/// reveal that it is a security guard page (INV-26: Error Parity).
///
/// Uses exclusively [VeraProbColors] tokens for all colors and adapts to
/// three breakpoints via [LayoutBuilder]:
/// - Desktop (≥1024 px): icon 96 px
/// - Tablet  (≥768 px):  icon 72 px
/// - Mobile  (<768 px):  icon 56 px
///
/// The "Voltar ao início" button pops the navigation stack to the root.
///
/// **INV-22:** Resides in `lib/features/super_admin/presentation/widgets/`.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double iconSize;
          if (constraints.maxWidth >= 1024) {
            iconSize = 96;
          } else if (constraints.maxWidth >= 768) {
            iconSize = 72;
          } else {
            iconSize = 56;
          }

          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VeraProbSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off,
                    size: iconSize,
                    color: VeraProbColors.textSecondary,
                  ),
                  const SizedBox(height: VeraProbSpacing.lg),
                  Text(
                    'Página não encontrada',
                    style: VeraProbTypography.sectionTitle.copyWith(
                      fontSize: 20,
                      color: VeraProbColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VeraProbSpacing.sm),
                  Text(
                    'O endereço que você tentou acessar não existe.',
                    style: VeraProbTypography.bodyMedium.copyWith(
                      color: VeraProbColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VeraProbSpacing.xl),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VeraProbColors.primary,
                      foregroundColor: VeraProbColors.background,
                      padding: const EdgeInsets.symmetric(
                        horizontal: VeraProbSpacing.lg,
                        vertical: VeraProbSpacing.md,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: VeraProbRadii.lgAll,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.home_outlined),
                        SizedBox(width: VeraProbSpacing.sm),
                        Text('Voltar ao início'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
