import 'package:flutter/material.dart';
import 'package:pactaflow/core/theme/app_theme.dart';

/// Placeholder for the Resource Management screen.
/// Will contain tabs for Drivers, Vehicles, and Routes management.
class ResourceManagementScreen extends StatelessWidget {
  const ResourceManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PactaFlowColors.background,
      child: Column(
        children: [
          // Tab bar
          Container(
            decoration: const BoxDecoration(
              color: PactaFlowColors.surface,
              border: Border(bottom: BorderSide(color: PactaFlowColors.border)),
            ),
            child: Row(
              children: [
                _Tab(
                  icon: Icons.person_outline,
                  label: 'Motoristas',
                  isSelected: true,
                ),
                _Tab(
                  icon: Icons.directions_bus_outlined,
                  label: 'Veículos',
                  isSelected: false,
                ),
                _Tab(
                  icon: Icons.route_outlined,
                  label: 'Rotas',
                  isSelected: false,
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: PactaFlowColors.scheduled.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'GESTÃO DE RECURSOS',
                    style: TextStyle(
                      color: PactaFlowColors.textSecondary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Motoristas, veículos e rotas com status em tempo real',
                    style: TextStyle(
                      color: PactaFlowColors.textDisabled,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;

  const _Tab({
    required this.icon,
    required this.label,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isSelected ? PactaFlowColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected
                ? PactaFlowColors.primary
                : PactaFlowColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? PactaFlowColors.textPrimary
                  : PactaFlowColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
