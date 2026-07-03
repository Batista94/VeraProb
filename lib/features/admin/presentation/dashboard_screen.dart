import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'widgets/contractual_risk_radar.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/projections/providers/feed_health_projection_provider.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/presentation/shell/widgets/onboarding_progress_banner.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/dashboard_risk_feed_provider.dart';
import 'package:veraprob/state/providers/sla_financial_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';

/// Tier-1 OCC dashboard: an asymmetric Bento grid prioritising actionable
/// financial signal over decoration. Left pane = financial KPIs (1-tap
/// drill-down) + telemetry confidence; right pane = the severity-sorted
/// command feed.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= VeraProbBreakpoints.wide;

        const leftPane = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FinancialKpiRow(),
            SizedBox(height: VeraProbSpacing.lg),
            _TelemetryConfidenceCard(),
          ],
        );

        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: VeraProbSpacing.xl,
            vertical: VeraProbSpacing.lg,
          ),
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              child: ref.watch(onboardingBannerVisibleProvider)
                  ? Padding(
                      padding: const EdgeInsets.only(
                        bottom: VeraProbSpacing.lg,
                      ),
                      child: OnboardingProgressBanner(
                        onNavigate: (destIdx) {
                          context.go(AdminNav.values[destIdx].path);
                          ref
                              .read(selectedContractIdProvider.notifier)
                              .set(null);
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const _DashboardHeader(),
            const SizedBox(height: VeraProbSpacing.xl),
            if (isWide)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: leftPane),
                  SizedBox(width: VeraProbSpacing.lg),
                  Expanded(flex: 1, child: RiskFeedList()),
                ],
              )
            else ...[
              leftPane,
              const SizedBox(height: VeraProbSpacing.lg),
              const RiskFeedList(),
            ],
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: VeraProbSpacing.lg,
      runSpacing: VeraProbSpacing.lg,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: VeraProbColors.surface,
                borderRadius: VeraProbRadii.xlAll,
                border: Border.all(color: VeraProbColors.border),
                boxShadow: VeraProbElevation.raised,
              ),
              child: const Icon(
                Icons.analytics_rounded,
                size: 32,
                color: VeraProbColors.primary,
              ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Painel de Controle',
                  style: VeraProbTypography.kpiValue.copyWith(
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
                        color: VeraProbColors.onTime,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Operação em Tempo Real • Receita Protegida',
                      style: VeraProbTypography.bodySmall.copyWith(
                        color: VeraProbColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        if (kDebugMode) const _DevSeedButton(),
      ],
    );
  }
}

/// Telemetry confidence promoted from the app-bar badge to a full KPI cell.
///
/// Interactive: hover highlights border; tap navigates to ingestion-health.
class _TelemetryConfidenceCard extends ConsumerStatefulWidget {
  const _TelemetryConfidenceCard();

  @override
  ConsumerState<_TelemetryConfidenceCard> createState() =>
      _TelemetryConfidenceCardState();
}

class _TelemetryConfidenceCardState
    extends ConsumerState<_TelemetryConfidenceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(feedHealthProjectionProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: VeraProbRadii.lgAll,
        onTap: () => context.go(AppRoutes.ingestionHealth),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: VeraProbColors.surfaceElevated,
            borderRadius: VeraProbRadii.lgAll,
            border: Border.all(
              color: _hovered
                  ? health.color.withValues(alpha: 0.6)
                  : health.color.withValues(alpha: 0.25),
              width: _hovered ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sensors_rounded, size: 16, color: health.color),
                  const SizedBox(width: 8),
                  Text(
                    'SAÚDE DA INGESTÃO DE TELEMETRIA',
                    style: VeraProbTypography.kpiLabel,
                  ),
                  const Spacer(),
                  Icon(
                    Icons.open_in_new,
                    size: 12,
                    color: VeraProbColors.textSecondary.withValues(
                      alpha: _hovered ? 1.0 : 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: health.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    health.label.toUpperCase(),
                    style: VeraProbTypography.kpiValue.copyWith(
                      color: health.color,
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: VeraProbSpacing.xs),
              Text(
                'Ver detalhes →',
                style: VeraProbTypography.kpiLabel.copyWith(
                  color: VeraProbColors.textSecondary.withValues(
                    alpha: _hovered ? 0.8 : 0.0,
                  ),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Debug-only operation simulator. Lives in its own widget so production
/// builds never reserve layout for it.
class _DevSeedButton extends ConsumerWidget {
  const _DevSeedButton();

  Future<void> _seedData(BuildContext context, WidgetRef ref) async {
    final organizationId = ref.read(currentOrganizationIdProvider);
    if (organizationId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(dataSeedingRepositoryProvider);
      await repository.seedCsvData(organizationId);
      await repository.seedDrivers(organizationId);
      await repository.seedRoutes(organizationId);
      await repository.seedHistoricalData(organizationId);
      await repository.seedActiveSanctions(organizationId);
      await runSanctionSimulation(
        ref,
        organizationId: organizationId,
        vehiclePlate: 'VPR-0001',
      );
      await repository.seedPhase9(organizationId);
      await ref
          .read(simulationSeedServiceProvider)
          .seedFinancialSnapshots(organizationId);

      // Invalidate cached providers so the onboarding checklist updates
      ref.invalidate(contractorListProvider);
      ref.invalidate(operationalZonesProvider);
      ref.invalidate(contractListProvider);
      ref.invalidate(slaTemplatesProvider);
      ref.invalidate(financialImpactProvider);
      ref.invalidate(financialSparklineProvider);
      ref.invalidate(dashboardRiskFeedProvider);
      ref.invalidate(activeAlertsProvider);

      messenger.showSnackBar(
        const SnackBar(content: Text('Dados de teste inseridos.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Erro ao inserir dados de simulação. Tente novamente.'),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      onPressed: () => _seedData(context, ref),
      icon: const Icon(Icons.bolt_rounded, size: 18),
      label: const Text('SIMULAR OPERAÇÃO'),
      style: ElevatedButton.styleFrom(
        backgroundColor: VeraProbColors.warning,
        // ACCENT-FILL-CONTRAST: dark foreground on accent fill.
        foregroundColor: VeraProbColors.background,
        elevation: 4,
      ),
    );
  }
}
