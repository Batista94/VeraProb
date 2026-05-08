import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/evidence_volume_card.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_health_card.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Aba de métricas operacionais de um tenant no painel SuperAdmin.
///
/// Exibe cards de KPIs (Contratos Ativos, Limite de Veículos, Última
/// Telemetria, Alertas Críticos) e o card de Volumetria de Evidências.
///
/// **INV-22:** Reside em `lib/features/super_admin/presentation/widgets/`.
/// **INV-11:** Construtores `const` onde possível; dados via provider.
///
/// Responsividade via [LayoutBuilder] com breakpoints:
/// - ≥ 1024px: 3+ colunas, espaçamento de 16px
/// - ≥ 768px e < 1024px: 2 colunas, espaçamento de 16px
/// - < 768px: coluna única, espaçamento de 12px
class TenantMetricsTab extends ConsumerWidget {
  final TenantHealthView tenant;
  const TenantMetricsTab({super.key, required this.tenant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evidenceAsync = ref.watch(evidenceVolumeProvider(tenant.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final spacing = width < 768 ? 12.0 : VeraProbSpacing.md;
          final columns = _columnsForWidth(width);
          final cardWidth = columns == 1
              ? width
              : (width - (columns - 1) * spacing) / columns;

          final cards = <Widget>[
            _buildCard(
              cardWidth,
              OrgHealthCard(
                title: 'Contratos Ativos',
                value: '${tenant.activeContractCount}',
                icon: Icons.description_outlined,
                valueColor: tenant.activeContractCount > 0
                    ? VeraProbColors.success
                    : VeraProbColors.textSecondary,
              ),
            ),
            _buildCard(
              cardWidth,
              OrgHealthCard(
                title: 'Limite de Veículos',
                value: tenant.maxVehicles == 0
                    ? 'Ilimitado'
                    : '${tenant.maxVehicles}',
                icon: Icons.local_shipping_outlined,
              ),
            ),
            _buildCard(
              cardWidth,
              OrgHealthCard(
                title: 'Última Telemetria',
                value: tenant.lastTelemetryAt != null
                    ? _formatDateTime(tenant.lastTelemetryAt!)
                    : 'Nunca',
                icon: Icons.satellite_alt_outlined,
                valueColor: tenant.lastTelemetryAt == null
                    ? VeraProbColors.textDisabled
                    : null,
              ),
            ),
            _buildCard(
              cardWidth,
              OrgHealthCard(
                title: 'Alertas Críticos',
                value: '${tenant.openCriticalAlertCount}',
                icon: Icons.warning_amber_outlined,
                valueColor: tenant.hasCriticalAlerts
                    ? VeraProbColors.error
                    : VeraProbColors.success,
              ),
            ),
            // Card de Volumetria de Evidências (Req 5.1)
            switch (evidenceAsync) {
              AsyncData(:final value) => _buildCard(
                cardWidth,
                EvidenceVolumeCard(
                  totalHistorical: value.totalHistorical,
                  totalMonthly: value.totalMonthly,
                ),
              ),
              AsyncLoading() => _buildCard(
                cardWidth,
                _EvidenceVolumePlaceholder(),
              ),
              AsyncError() => _buildCard(cardWidth, _EvidenceVolumeErrorCard()),
            },
          ];

          return Wrap(spacing: spacing, runSpacing: spacing, children: cards);
        },
      ),
    );
  }

  /// Calcula o número de colunas com base na largura disponível.
  ///
  /// Breakpoints (Req 6.1–6.3):
  /// - ≥ 1024px → 3+ colunas (máximo baseado na largura)
  /// - ≥ 768px e < 1024px → 2 colunas
  /// - < 768px → 1 coluna
  static int _columnsForWidth(double width) {
    if (width >= 1024) {
      // Calcula quantas colunas de ~240px cabem, mínimo 3
      final cols = (width / 260).floor();
      return cols < 3 ? 3 : cols;
    }
    if (width >= 768) return 2;
    return 1;
  }

  /// Envolve um card com [SizedBox] de largura responsiva.
  static Widget _buildCard(double cardWidth, Widget child) {
    return SizedBox(width: cardWidth, child: child);
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Placeholder exibido enquanto os dados de volumetria estão carregando.
class _EvidenceVolumePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(VeraProbSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.storage_outlined,
                  size: 18,
                  color: VeraProbColors.textSecondary,
                ),
                const SizedBox(width: VeraProbSpacing.sm),
                Text(
                  'Volumetria de Evidências',
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: VeraProbColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de erro exibido quando a carga de volumetria falha.
class _EvidenceVolumeErrorCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(VeraProbSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.storage_outlined,
                  size: 18,
                  color: VeraProbColors.textSecondary,
                ),
                const SizedBox(width: VeraProbSpacing.sm),
                Text(
                  'Volumetria de Evidências',
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: VeraProbColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: VeraProbColors.error,
                ),
                const SizedBox(width: VeraProbSpacing.xs),
                Text(
                  'Erro ao carregar dados',
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: VeraProbColors.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
