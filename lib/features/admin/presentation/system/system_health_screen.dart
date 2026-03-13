import 'package:flutter/material.dart';
import 'package:pactaflow/core/theme/app_theme.dart';

/// Placeholder for the System Health screen.
/// Will display feed statuses, audit logs, and system diagnostics.
class SystemHealthScreen extends StatelessWidget {
  const SystemHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PactaFlowColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SAÚDE DO SISTEMA',
            style: TextStyle(
              color: PactaFlowColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Feed status cards
          _FeedStatusCard(
            name: 'SPTrans Olho Vivo',
            status: 'Aguardando conexão',
            isOnline: false,
            lastUpdate: '—',
          ),
          const SizedBox(height: 12),
          _FeedStatusCard(
            name: 'GTFS Static (São Paulo)',
            status: 'Não importado',
            isOnline: false,
            lastUpdate: '—',
          ),
          const SizedBox(height: 12),
          _FeedStatusCard(
            name: 'Supabase Realtime',
            status: 'Aguardando configuração',
            isOnline: false,
            lastUpdate: '—',
          ),

          const SizedBox(height: 32),

          // Audit log placeholder
          const Text(
            'LOG DE AUDITORIA',
            style: TextStyle(
              color: PactaFlowColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: PactaFlowColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: PactaFlowColors.border),
              ),
              child: const Center(
                child: Text(
                  'Nenhum evento registrado',
                  style: TextStyle(
                    color: PactaFlowColors.textDisabled,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedStatusCard extends StatelessWidget {
  final String name;
  final String status;
  final bool isOnline;
  final String lastUpdate;

  const _FeedStatusCard({
    required this.name,
    required this.status,
    required this.isOnline,
    required this.lastUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isOnline
        ? PactaFlowColors.onTime
        : PactaFlowColors.textDisabled;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PactaFlowColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PactaFlowColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: PactaFlowTypography.bodyMedium),
                const SizedBox(height: 2),
                Text(status, style: PactaFlowTypography.caption),
              ],
            ),
          ),
          Text('Último: $lastUpdate', style: PactaFlowTypography.caption),
        ],
      ),
    );
  }
}
