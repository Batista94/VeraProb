import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Card de volumetria de evidências para a aba de Métricas do SuperAdmin.
///
/// Exibe o total histórico de evidências como valor principal (KPI) e o
/// total do mês corrente como valor secundário, sobre um gradiente visual
/// premium (primary → secondary).
///
/// **INV-11:** Construtor `const` — sem estado local.
/// **INV-22:** Reside em `lib/features/super_admin/presentation/widgets/`.
///
/// Exemplo de uso:
/// ```dart
/// EvidenceVolumeCard(
///   totalHistorical: 15432,
///   totalMonthly: 287,
/// )
/// ```
class EvidenceVolumeCard extends StatelessWidget {
  /// Total acumulado de evidências desde a criação do tenant.
  final int totalHistorical;

  /// Total de evidências registradas no mês corrente.
  final int totalMonthly;

  /// Cria um card de volumetria de evidências.
  const EvidenceVolumeCard({
    super.key,
    required this.totalHistorical,
    required this.totalMonthly,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.storage_outlined,
                    size: 18,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Volumetria de Evidências',
                      style: VeraProbTypography.bodySmall.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _formatNumber(totalHistorical),
                style: VeraProbTypography.kpiValue.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Este mês: ${_formatNumber(totalMonthly)}',
                style: VeraProbTypography.bodySmall.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formata números grandes com separador de milhar para legibilidade.
  ///
  /// Exemplo: `15432` → `"15.432"` (locale pt_BR).
  String _formatNumber(int value) {
    return NumberFormat.decimalPattern('pt_BR').format(value);
  }
}
