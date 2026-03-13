import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../state/providers/auth_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operatorName = ref.watch(currentOperatorNameProvider);
    final operatorId = ref.watch(currentOperatorIdProvider);

    return Scaffold(
      backgroundColor: PactaFlowColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONFIGURAÇÕES DO SISTEMA',
                    style: PactaFlowTypography.sectionTitle.copyWith(
                      color: PactaFlowColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gerencie as preferências globais do Centro de Controle.',
                    style: PactaFlowTypography.bodySmall,
                  ),
                  const SizedBox(height: 32),

                  // ── Seção: Sessão Atual ────────────────
                  _SectionHeader(title: 'Sessão Atual'),
                  _SettingTile(
                    label: 'Operador Conectado',
                    value: operatorName,
                    icon: Icons.person_outline,
                  ),
                  _SettingTile(
                    label: 'ID do Operador',
                    value: operatorId ?? 'Não autenticado',
                    icon: Icons.badge_outlined,
                  ),

                  const SizedBox(height: 32),

                  // ── Seção: Conectividade ───────────────
                  _SectionHeader(title: 'Dados e Conectividade'),
                  const _SettingTile(
                    label: 'Telemetria',
                    value: 'Real-time (Supabase)',
                    icon: Icons.sensors,
                  ),

                  const SizedBox(height: 32),

                  // ── Seção: Informações Técnicas ───────
                  _SectionHeader(title: 'Sobre a Plataforma'),
                  const _SettingTile(
                    label: 'Versão do Software',
                    value: '1.0.0-mvp.hardening',
                    icon: Icons.info_outline,
                  ),
                  const _SettingTile(
                    label: 'Ambiente',
                    value: 'Desenvolvimento / Simulação',
                    icon: Icons.code,
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: PactaFlowTypography.caption.copyWith(
            color: PactaFlowColors.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Divider(height: 24, color: PactaFlowColors.border),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SettingTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: PactaFlowColors.textSecondary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: PactaFlowTypography.caption),
              Text(
                value,
                style: PactaFlowTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
