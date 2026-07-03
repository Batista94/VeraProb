import 'package:flutter/material.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Header row for the Routes tab — title + "Cadastrar rota" button.
class RouteTabHeader extends StatelessWidget {
  final UserRole userRole;
  final VoidCallback onAddPressed;

  const RouteTabHeader({
    super.key,
    required this.userRole,
    required this.onAddPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: VeraProbRadii.lgAll,
          ),
          child: Icon(Icons.route, size: 28, color: colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rotas Operacionais',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cadastro de rotas vinculadas à operação da organização.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (userRole.hasPermission(UserRole.admin))
          FilledButton.icon(
            onPressed: onAddPressed,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Cadastrar rota'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
