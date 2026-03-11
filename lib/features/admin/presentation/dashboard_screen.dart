import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/charts_section.dart';
import 'widgets/heatmap_section.dart';
import '../../../core/config/supabase_client.dart';
import '../../../core/utils/data_seeder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../application/adapters/stress_scenario_config.dart';
import '../../../../state/providers/fleet_providers.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<void> _seedData(BuildContext context) async {
    try {
      final seeder = DataSeeder(supabase);
      await seeder.seedDrivers();
      await seeder.seedRoutes();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dados de teste inseridos com sucesso! 🚀'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao inserir dados: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              spacing: 24,
              runSpacing: 24,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: BusFlowColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: BusFlowColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.analytics_rounded, 
                        size: 32, color: BusFlowColors.primary),
                    ),
                    const SizedBox(width: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Painel de Controle',
                          style: BusFlowTypography.kpiValue.copyWith(
                            fontSize: 32,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: BusFlowColors.onTime,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Operação em Tempo Real • Receita Protegida',
                              style: BusFlowTypography.bodySmall.copyWith(
                                color: BusFlowColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _seedData(context),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text('SIMULAR OPERAÇÃO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade900,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: Colors.amber.shade900.withValues(alpha: 0.3),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 40),
        const ChartsSection(),
        const SizedBox(height: 32),
        const HeatmapSection(),
        const SizedBox(height: 40),
      ],
    );
  }
}
