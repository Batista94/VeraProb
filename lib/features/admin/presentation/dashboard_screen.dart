import 'package:flutter/material.dart';
import 'widgets/charts_section.dart';
import 'widgets/heatmap_section.dart';
import '../../../core/config/supabase_client.dart';
import '../../../core/utils/data_seeder.dart';

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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dashboard, size: 32, color: Colors.blueGrey),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Visão Geral',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text('Monitoramento de frota e métricas'),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _seedData(context),
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Carregar Dados Teste'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const ChartsSection(),
          const SizedBox(height: 24),
          const HeatmapSection(),
        ],
      ),
    );
  }
}
