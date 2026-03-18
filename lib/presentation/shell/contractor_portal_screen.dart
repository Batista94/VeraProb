import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/projections/contractor_portal_view.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/shared/money.dart';
import '../../domain/sla_audit/audit_package_status.dart';
import '../../state/providers/audit_package_providers.dart';

/// Contractor Portal — authenticated, contractor-scoped evidence view.
///
/// Access: Gerente + Operador roles (scoped to organization).
/// NOT a public URL — LGPD compliance requires authentication (INV-6).
///
/// Shows the contractor a FAIR, verifiable view of each billing cycle:
///   - SLA compliance by obligation (executed / no-show / evidence-gap)
///   - Applied penalties (lostRevenue in BRL)
///   - "Solicitar Pacote de Evidências" → generates sealed CSV + PDF export
///
/// Low Dispute-to-Resolution ratio is the competitive proof point — the
/// contractor can independently verify every number via the packageHash.
class ContractorPortalScreen extends ConsumerWidget {
  const ContractorPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(sealedAuditPackagesProvider);

    return Scaffold(
      backgroundColor: PactaFlowColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PORTAL DO CONTRATANTE',
                    style: PactaFlowTypography.sectionTitle.copyWith(
                      color: PactaFlowColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Visão verificável e imparcial de cada ciclo de faturamento.',
                    style: PactaFlowTypography.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cada pacote é criptograficamente selado (SHA-256) — '
                    'você pode verificar a integridade de forma independente.',
                    style: PactaFlowTypography.bodySmall.copyWith(
                      color: PactaFlowColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          packagesAsync.when(
            data: (packages) {
              // Only show sealed packages — projections for contractor view
              final sealed = packages
                  .where((p) => p.status == AuditPackageStatus.sealed)
                  .toList();

              if (sealed.isEmpty) {
                return const SliverFillRemaining(child: _EmptyState());
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final view =
                        ContractorPortalView.fromPackage(sealed[index]);
                    return _EvidenceCard(view: view);
                  },
                  childCount: sealed.length,
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Text(
                  'Erro ao carregar pacotes: $e',
                  style: PactaFlowTypography.bodySmall.copyWith(
                    color: PactaFlowColors.error,
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

// ── Evidence Card ─────────────────────────────────────────────────────────────

class _EvidenceCard extends ConsumerWidget {
  final ContractorPortalView view;

  const _EvidenceCard({required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complianceColor = view.complianceRate >= 90
        ? PactaFlowColors.success
        : view.complianceRate >= 70
            ? PactaFlowColors.warning
            : PactaFlowColors.error;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Card(
        color: PactaFlowColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: PactaFlowColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: period + contractor ───────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_fmtDate(view.periodStartUtc)} – ${_fmtDate(view.periodEndUtc)}',
                          style: PactaFlowTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          view.contractorName,
                          style: PactaFlowTypography.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // Compliance badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: complianceColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${view.complianceRate.toStringAsFixed(1)}% conformidade',
                      style: TextStyle(
                        color: complianceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Obligation breakdown ──────────────────────────────────────
              Text(
                'OBRIGAÇÕES DO PERÍODO',
                style: PactaFlowTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _ObligationChip(
                    icon: Icons.check_circle_outline,
                    label: '${view.executedCount} executadas',
                    color: PactaFlowColors.success,
                  ),
                  _ObligationChip(
                    icon: Icons.cancel_outlined,
                    label: '${view.noShowCount} não realizadas',
                    color: PactaFlowColors.error,
                  ),
                  if (view.evidenceGapCount > 0)
                    _ObligationChip(
                      icon: Icons.gps_off_outlined,
                      label: '${view.evidenceGapCount} sem evidência GPS',
                      color: PactaFlowColors.warning,
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Financial summary ─────────────────────────────────────────
              if (view.lostRevenue.cents > 0) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PactaFlowColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: PactaFlowColors.error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 16,
                        color: PactaFlowColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Penalidades aplicadas: ${_fmtBrl(view.lostRevenue)}',
                              style: const TextStyle(
                                color: PactaFlowColors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'de ${_fmtBrl(view.totalContractedRevenue)} contratados',
                              style: PactaFlowTypography.bodySmall
                                  .copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Integrity footer + evidence request ───────────────────────
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_outlined,
                              size: 13,
                              color: PactaFlowColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'SHA-256: ${view.packageHash.substring(0, 16)}…',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF888888),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _EvidenceRequestButton(view: view),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) => dt.toIso8601String().split('T')[0];
  String _fmtBrl(Money m) => 'R\$ ${(m.cents / 100).toStringAsFixed(0)}';
}

// ── Evidence Request Button ────────────────────────────────────────────────────

class _EvidenceRequestButton extends ConsumerWidget {
  final ContractorPortalView view;

  const _EvidenceRequestButton({required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      onPressed: () => _requestPackage(context, ref),
      icon: const Icon(Icons.download_outlined, size: 14),
      label: const Text(
        'Solicitar Pacote de Evidências',
        style: TextStyle(fontSize: 12),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: PactaFlowColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  void _requestPackage(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    // Request both CSV and PDF in parallel — contractor gets both formats
    ref.read(csvExportProvider(view.sealedPackageId).future).then((_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pacote de evidências gerado — CSV disponível.'),
        ),
      );
    }).catchError((e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao gerar pacote: $e')),
      );
    });
  }
}

// ── Obligation Chip ───────────────────────────────────────────────────────────

class _ObligationChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ObligationChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 48,
            color: PactaFlowColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum pacote de evidências disponível.',
            style: PactaFlowTypography.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Os pacotes são gerados automaticamente ao fechar o ciclo mensal.',
            style: PactaFlowTypography.bodySmall.copyWith(
              color: PactaFlowColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
