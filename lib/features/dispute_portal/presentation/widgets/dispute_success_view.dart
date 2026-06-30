import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/core/theme/app_theme.dart';

const double _kSuccessTitleFontSize = 18.0;
const TextStyle _kMonospaceProtocolStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: VeraProbColors.textPrimary,
);

class DisputeSuccessView extends StatelessWidget {
  final DateTime submittedAtUtc;
  final String protocol;

  const DisputeSuccessView({
    super.key,
    required this.submittedAtUtc,
    required this.protocol,
  });

  @override
  Widget build(BuildContext context) {
    final localTime = submittedAtUtc.toLocal();
    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
    final timeFormat = DateFormat('HH:mm', 'pt_BR');

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VeraProbColors.border.withValues(alpha: 0.1)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: VeraProbColors.success,
            size: 64,
          ),
          const SizedBox(height: 24),
          Text(
            'Contestação Recebida com Sucesso',
            style: VeraProbTypography.sectionTitle.copyWith(
              fontSize: _kSuccessTitleFontSize,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Sua defesa foi registrada e será analisada pela equipe de auditoria.',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: VeraProbColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoRow(
                  'Data e Hora:',
                  '${dateFormat.format(localTime)} às ${timeFormat.format(localTime)}',
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Protocolo:', protocol, isMonospace: true),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Você pode fechar esta janela com segurança.',
            style: VeraProbTypography.badge.copyWith(
              color: VeraProbColors.textDisabled,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isMonospace = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: VeraProbTypography.badge.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: isMonospace
              ? _kMonospaceProtocolStyle
              : VeraProbTypography.dataValue.copyWith(
                  fontWeight: FontWeight.w600,
                ),
        ),
      ],
    );
  }
}
