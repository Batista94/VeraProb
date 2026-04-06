import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/projections/executive_dashboard_view.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/sla_audit/shadow_mode_simulation.dart';
import '../../state/providers/executive_dashboard_providers.dart';

/// Executive Dashboard — Financial Protection Score + CFO KPIs.
///
/// Access: Gerente role only (RBAC enforced at routing layer).
///
/// Shows:
///   - Financial Protection Score (FPS) radial zone indicator
///   - 5 CFO KPIs: Receita Blindada, Taxa de Recuperação, Dispute-to-Resolution,
///     FPS, SLA Compliance Trend
///   - Shadow Mode ROI card (if simulation available)
///   - Evidence Quality Attribution (protects operator when hardware is poor)
class ExecutiveDashboardScreen extends ConsumerWidget {
  const ExecutiveDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(executiveDashboardProvider);

    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: dashboardAsync.when(
        data: (dashboard) => _DashboardBody(dashboard: dashboard),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Erro ao carregar dashboard: $e',
            style: VeraProbTypography.bodySmall.copyWith(
              color: VeraProbColors.error,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final ExecutiveDashboardView dashboard;

  const _DashboardBody({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DASHBOARD EXECUTIVO',
                  style: VeraProbTypography.sectionTitle.copyWith(
                    color: VeraProbColors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmtDate(dashboard.periodStartUtc)} – ${_fmtDate(dashboard.periodEndUtc)}',
                  style: VeraProbTypography.bodySmall,
                ),
                const SizedBox(height: 24),

                // ── FPS Zone Banner ──────────────────────────────────────
                _FpsZoneBanner(dashboard: dashboard),
                const SizedBox(height: 24),

                // ── KPI Grid ─────────────────────────────────────────────
                _KpiGrid(dashboard: dashboard),
                const SizedBox(height: 24),

                // ── Revenue Distribution ─────────────────────────────────
                _RevenueSection(dashboard: dashboard),
                const SizedBox(height: 24),

                // ── Evidence Quality Attribution ─────────────────────────
                if (dashboard.latestShadowMode != null) ...[
                  _EvidenceAttributionCard(
                    attribution:
                        dashboard.latestShadowMode!.evidenceQualityAttribution,
                    evidenceScore: dashboard.evidenceScore,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Shadow Mode ROI ───────────────────────────────────────
                if (dashboard.latestShadowMode != null)
                  _ShadowModeCard(simulation: dashboard.latestShadowMode!),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime dt) => dt.toIso8601String().split('T')[0];
}

// ── FPS Zone Banner ──────────────────────────────────────────────────────────

class _FpsZoneBanner extends StatelessWidget {
  final ExecutiveDashboardView dashboard;

  const _FpsZoneBanner({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final fps = dashboard.financialProtectionScore / 100.0;
    final zone = dashboard.fpsZone;

    final (color, label) = switch (zone) {
      FpsZone.protected => (VeraProbColors.success, 'PROTEÇÃO FORTE'),
      FpsZone.moderate => (VeraProbColors.warning, 'PROTEÇÃO ADEQUADA'),
      FpsZone.highRisk => (VeraProbColors.error, 'PROTEÇÃO INSUFICIENTE'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financial Protection Score',
                  style: VeraProbTypography.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${fps.toStringAsFixed(1)} / 100',
                  style: VeraProbTypography.sectionTitle.copyWith(
                    color: color,
                    fontSize: 32,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── KPI Grid ─────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final ExecutiveDashboardView dashboard;

  const _KpiGrid({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _KpiCard(
          title: 'Receita Blindada',
          value: _fmtBrl(dashboard.protectedRevenue),
          subtitle:
              'de ${_fmtBrl(dashboard.totalContractedRevenue)} contratados',
          color: VeraProbColors.success,
          icon: Icons.shield_outlined,
        ),
        _KpiCard(
          title: 'Taxa de Recuperação',
          value:
              '${(dashboard.penaltyRecoveryRate / 100.0).toStringAsFixed(1)}%',
          subtitle: 'penalidades recuperadas',
          color: VeraProbColors.primary,
          icon: Icons.trending_up,
        ),
        _KpiCard(
          title: 'Dispute-to-Resolution',
          value:
              '${(dashboard.disputeToResolutionRatio / 100.0).toStringAsFixed(1)}%',
          subtitle: 'compensações / no-shows',
          color: VeraProbColors.warning,
          icon: Icons.balance_outlined,
        ),
        _KpiCard(
          title: 'Conformidade SLA',
          value: '${(dashboard.complianceScore / 100.0).toStringAsFixed(1)}%',
          subtitle:
              '${dashboard.executedCount} / ${dashboard.totalObligations} obrigações',
          color: VeraProbColors.primary,
          icon: Icons.check_circle_outline,
        ),
        if (dashboard.latestShadowMode != null)
          _KpiCard(
            title: 'Economia BRL',
            value: _fmtBrl(dashboard.latestShadowModeRevenueCents!),
            subtitle: 'receita protegida pela plataforma',
            color: VeraProbColors.success,
            icon: Icons.savings_outlined,
          ),
      ],
    );
  }

  String _fmtBrl(int cents) => 'R\$ ${(cents / 100).toStringAsFixed(0)}';
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        color: VeraProbColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title, style: VeraProbTypography.bodySmall),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: VeraProbTypography.sectionTitle.copyWith(
                  color: color,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: VeraProbTypography.bodySmall.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Revenue Distribution ─────────────────────────────────────────────────────

class _RevenueSection extends StatelessWidget {
  final ExecutiveDashboardView dashboard;

  const _RevenueSection({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final total = dashboard.totalContractedRevenue;
    if (total == 0) return const SizedBox.shrink();

    final protectedPct = dashboard.protectedRevenue / total;
    final atRiskPct = dashboard.revenueAtRisk / total;
    final lostPct = dashboard.lostRevenue / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DISTRIBUIÇÃO DE RECEITA',
          style: VeraProbTypography.bodySmall.copyWith(
            letterSpacing: 1.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              if (protectedPct > 0)
                Expanded(
                  flex: (protectedPct * 100).round(),
                  child: Container(height: 24, color: VeraProbColors.success),
                ),
              if (atRiskPct > 0)
                Expanded(
                  flex: (atRiskPct * 100).round(),
                  child: Container(height: 24, color: VeraProbColors.warning),
                ),
              if (lostPct > 0)
                Expanded(
                  flex: (lostPct * 100).round(),
                  child: Container(height: 24, color: VeraProbColors.error),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _Legend(
              color: VeraProbColors.success,
              label: 'Blindada ${(protectedPct * 100).toStringAsFixed(0)}%',
            ),
            _Legend(
              color: VeraProbColors.warning,
              label: 'Em Risco ${(atRiskPct * 100).toStringAsFixed(0)}%',
            ),
            _Legend(
              color: VeraProbColors.error,
              label: 'Perdida ${(lostPct * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ── Evidence Quality Attribution ─────────────────────────────────────────────

class _EvidenceAttributionCard extends StatelessWidget {
  final String attribution;
  final int evidenceScore;

  const _EvidenceAttributionCard({
    required this.attribution,
    required this.evidenceScore,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = evidenceScore < 8000;
    final color = isLow ? VeraProbColors.warning : VeraProbColors.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLow ? Icons.info_outline : Icons.verified_outlined,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                'QUALIDADE DE EVIDÊNCIA — ${(evidenceScore / 100.0).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            attribution,
            style: VeraProbTypography.bodySmall.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Shadow Mode ROI Card ──────────────────────────────────────────────────────

class _ShadowModeCard extends StatelessWidget {
  final ShadowModeSimulation simulation;

  const _ShadowModeCard({required this.simulation});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VeraProbColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: VeraProbColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, size: 16),
              const SizedBox(width: 6),
              Text(
                'SHADOW MODE — ROI DA PLATAFORMA',
                style: VeraProbTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(simulation.simulationName, style: VeraProbTypography.bodySmall),
          const SizedBox(height: 4),
          Text(
            'ROI: ${(simulation.roiPercentageBps / 100).toStringAsFixed(1)}%',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.primary,
              fontSize: 24,
            ),
          ),
        ],
      ),
    );
  }
}
