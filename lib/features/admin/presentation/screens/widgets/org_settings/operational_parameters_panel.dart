import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';

/// Seção 2 das Configurações da Organização: parâmetros operacionais de
/// negócio (sliders) + justificativa obrigatória.
///
/// Stateless — o parent `_OrgSettingsScreenState` é dono de
/// `_dwellTimeSeconds`, `_maxKinematicSpeedKmh`, da `opParamsFormKey` e do
/// handler de salvamento. Mutações dos sliders são surfaceadas via
/// [onDwellChanged] / [onSpeedChanged].
class OperationalParametersPanel extends StatelessWidget {
  const OperationalParametersPanel({
    super.key,
    required this.opParamsFormKey,
    required this.dwellTimeSeconds,
    required this.maxKinematicSpeedKmh,
    required this.opReasonController,
    required this.isSavingOpParams,
    required this.onDwellChanged,
    required this.onSpeedChanged,
    required this.onSave,
  });

  final GlobalKey<FormState> opParamsFormKey;
  final int dwellTimeSeconds;
  final double maxKinematicSpeedKmh; // Physical Metric - Double Required
  final TextEditingController opReasonController;
  final bool isSavingOpParams;
  final ValueChanged<int> onDwellChanged;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.speed_outlined,
              size: 18,
              color: VeraProbColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Parâmetros Operacionais',
              style: VeraProbTypography.sectionTitle.copyWith(fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Configurações de negócio editáveis pelo Admin da Organização. '
          'Estas são configurações operacionais — não financeiras.',
          style: VeraProbTypography.bodyMedium.copyWith(
            color: VeraProbColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        Form(
          key: opParamsFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dwell time slider
              Text(
                'Tempo de Parada (Fechamento Automático)',
                style: VeraProbTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${dwellTimeSeconds}s (~${(dwellTimeSeconds / 60).round()} min) '
                '— tempo sem movimento para fechar parada automaticamente.',
                style: VeraProbTypography.bodyMedium.copyWith(
                  color: VeraProbColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              SliderTheme(
                data: const SliderThemeData(
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                  trackHeight: 2,
                  activeTrackColor: VeraProbColors.primary,
                  inactiveTrackColor: VeraProbColors.border,
                  thumbColor: VeraProbColors.primary,
                ),
                child: Slider(
                  value: dwellTimeSeconds.toDouble(),
                  min: 60,
                  max: 1800,
                  divisions: 29,
                  label: '${dwellTimeSeconds}s',
                  onChanged: (v) => onDwellChanged(v.round()),
                ),
              ),
              const SizedBox(height: 20),

              // Speed slider
              Text(
                'Velocidade Máxima para Alerta (km/h)',
                style: VeraProbTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${maxKinematicSpeedKmh.toStringAsFixed(0)} km/h '
                '— velocidade acima desta marca gera alerta no monitor.',
                style: VeraProbTypography.bodyMedium.copyWith(
                  color: VeraProbColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              SliderTheme(
                data: const SliderThemeData(
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                  trackHeight: 2,
                  activeTrackColor: VeraProbColors.primary,
                  inactiveTrackColor: VeraProbColors.border,
                  thumbColor: VeraProbColors.primary,
                ),
                child: Slider(
                  value: maxKinematicSpeedKmh.clamp(
                    10.0,
                    200.0,
                  ), // Physical Metric - Double Required
                  min: 10,
                  max: 200,
                  divisions: 38,
                  label: '${maxKinematicSpeedKmh.toStringAsFixed(0)} km/h',
                  onChanged: (v) => onSpeedChanged(
                    v, // Physical Metric - Double Required
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Reason (mandatory for operational changes)
              Text(
                'Justificativa *',
                style: VeraProbTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Obrigatória para mudanças de parâmetros operacionais (auditoria).',
                style: VeraProbTypography.bodyMedium.copyWith(
                  color: VeraProbColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: opReasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText:
                      'Ex: Ajuste de velocidade após mudança de rota pela empresa X',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Justificativa é obrigatória';
                  }
                  if (v.trim().length < 10) {
                    return 'Mínimo de 10 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: isSavingOpParams
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.tune_outlined),
                  label: const Text('Salvar Parâmetros Operacionais'),
                  onPressed: isSavingOpParams ? null : onSave,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
