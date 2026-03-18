import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/sla_audit/audit_package.dart';
import '../../state/providers/audit_package_providers.dart';

/// Screen listing sealed [AuditPackage] records for the current organization.
///
/// Access: Gerente + Operador roles.
/// Allows downloading CSV and PDF exports for each sealed package.
class BillingCycleReportsScreen extends ConsumerWidget {
  const BillingCycleReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(sealedAuditPackagesProvider);

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
                    'RELATÓRIOS DE CICLO DE FATURAMENTO',
                    style: PactaFlowTypography.sectionTitle.copyWith(
                      color: PactaFlowColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pacotes de auditoria selados com garantia de integridade SHA-256.',
                    style: PactaFlowTypography.bodySmall,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          packagesAsync.when(
            data: (packages) => packages.isEmpty
                ? const SliverFillRemaining(child: _EmptyState())
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _PackageCard(package: packages[index]),
                      childCount: packages.length,
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Text(
                  'Erro ao carregar relatórios: $e',
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

class _PackageCard extends ConsumerWidget {
  final AuditPackage package;

  const _PackageCard({required this.package});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateRange =
        '${_fmtDate(package.periodStartUtc)} – ${_fmtDate(package.periodEndUtc)}';
    final compliance = '${package.complianceRate.toStringAsFixed(1)}%';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Card(
        color: PactaFlowColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: PactaFlowColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ── Period & metadata ──────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateRange,
                      style: PactaFlowTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package.contractorName,
                      style: PactaFlowTypography.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _Badge(label: 'Conformidade $compliance'),
                        const SizedBox(width: 8),
                        _Badge(
                          label: 'SHA-256',
                          color: PactaFlowColors.primary.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // ── Export buttons ─────────────────────────────────────────
              Column(
                children: [
                  _ExportButton(
                    label: 'CSV',
                    icon: Icons.table_chart_outlined,
                    onTap: () => _downloadCsv(context, ref),
                  ),
                  const SizedBox(height: 8),
                  _ExportButton(
                    label: 'PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    onTap: () => _downloadPdf(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _downloadCsv(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    ref
        .read(csvExportProvider(package.id).future)
        .then((_) {
          messenger.showSnackBar(
            const SnackBar(content: Text('CSV gerado com sucesso.')),
          );
        })
        .catchError((e) {
          messenger.showSnackBar(
            SnackBar(content: Text('Erro ao gerar CSV: $e')),
          );
        });
  }

  void _downloadPdf(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    ref
        .read(pdfExportProvider(package.id).future)
        .then((_) {
          messenger.showSnackBar(
            const SnackBar(content: Text('PDF gerado com sucesso.')),
          );
        })
        .catchError((e) {
          messenger.showSnackBar(
            SnackBar(content: Text('Erro ao gerar PDF: $e')),
          );
        });
  }

  String _fmtDate(DateTime dt) => dt.toIso8601String().split('T')[0];
}

class _ExportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ExportButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color? color;

  const _Badge({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? PactaFlowColors.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 48,
            color: PactaFlowColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum pacote de auditoria selado.',
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
