import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/core/theme/app_theme.dart';

class DisputeContextCard extends StatelessWidget {
  final InfractionContextProjection contextData;

  const DisputeContextCard({super.key, required this.contextData});

  @override
  Widget build(BuildContext context) {
    final penaltyValue =
        'R\$ ${(contextData.penaltyValueCents / 100).toStringAsFixed(2).replaceAll('.', ',')}';
    final occurredAtBrt = contextData.occurredAtUtc
        .toLocal(); // Ideally we format properly
    final occurredAtString =
        '${occurredAtBrt.day.toString().padLeft(2, '0')}/${occurredAtBrt.month.toString().padLeft(2, '0')}/${occurredAtBrt.year} ${occurredAtBrt.hour.toString().padLeft(2, '0')}:${occurredAtBrt.minute.toString().padLeft(2, '0')}';

    return Card(
      elevation: 0,
      color: VeraProbColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: VeraProbColors.border),
      ),
      child: Padding(
        padding: VeraProbSpacing.sectionPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('DADOS DA INFRAÇÃO', style: VeraProbTypography.fieldLabel),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: VeraProbColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: VeraProbColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'DADOS IMUTÁVEIS',
                    style: VeraProbTypography.badge.copyWith(
                      color: VeraProbColors.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: VeraProbSpacing.md),
            _buildDataRow(
              'Ativo',
              contextData.assetIdentifier,
              'Data (Horário de Brasília)',
              occurredAtString,
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            _buildDataRow(
              'Localização',
              contextData.locationLabel,
              'Valor',
              penaltyValue,
              value2Color: VeraProbColors.error,
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            _buildDataRow(
              'Medido',
              contextData.measuredValue?.toString() ?? '-',
              'Limite',
              contextData.thresholdValue?.toString() ?? '-',
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Excesso', style: VeraProbTypography.fieldLabel),
                      const SizedBox(height: VeraProbSpacing.xs),
                      Text(
                        '+${contextData.exceededBy ?? '-'}',
                        style: VeraProbTypography.dataValue.copyWith(
                          color: VeraProbColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ID do Registro',
                        style: VeraProbTypography.fieldLabel,
                      ),
                      const SizedBox(height: VeraProbSpacing.xs),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: contextData.recordId),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'ID copiado para a área de transferência',
                              ),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              contextData.recordId,
                              style: VeraProbTypography.dataValue.copyWith(
                                fontFamily: 'Courier',
                              ),
                            ),
                            const SizedBox(width: VeraProbSpacing.xs),
                            const Icon(
                              Icons.copy,
                              size: 14,
                              color: VeraProbColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(
    String label1,
    String value1,
    String label2,
    String value2, {
    Color? value2Color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label1, style: VeraProbTypography.fieldLabel),
              const SizedBox(height: VeraProbSpacing.xs),
              Text(value1, style: VeraProbTypography.dataValue),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label2, style: VeraProbTypography.fieldLabel),
              const SizedBox(height: VeraProbSpacing.xs),
              Text(
                value2,
                style: VeraProbTypography.dataValue.copyWith(
                  color: value2Color ?? VeraProbColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
