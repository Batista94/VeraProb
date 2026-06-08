import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/sla_audit/smart_defaults_service.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';
import 'package:veraprob/presentation/shared/ui/info_tooltip.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/declare_plan_ui_utils.dart';

/// Step 3 of the Declare Contract Plan wizard — SLA & Penalties.
///
/// All controller mutations (apply-template, save-as-template) are handled
/// internally so the parent form does not need to duplicate this logic.
/// Only [onContinue] is surfaced as a callback.
class Step3SlaPenalties extends ConsumerWidget {
  const Step3SlaPenalties({
    super.key,
    required this.baseValueController,
    required this.delayToleranceController,
    required this.earlyArrivalToleranceController,
    required this.dwellTimeController,
    required this.gracePeriodController,
    required this.noShowMultiplierController,
    required this.noShowThresholdController,
    required this.delayMinuteValueController,
    required this.downgradeValueController,
    required this.baseValueFocus,
    required this.delayToleranceFocus,
    required this.noShowMultiplierFocus,
    required this.delayMinuteValueFocus,
    required this.downgradeValueFocus,
    required this.earlyArrivalFocus,
    required this.dwellTimeFocus,
    required this.noShowThresholdFocus,
    required this.gracePeriodFocus,
    required this.onContinue,
  });

  final TextEditingController baseValueController;
  final TextEditingController delayToleranceController;
  final TextEditingController earlyArrivalToleranceController;
  final TextEditingController dwellTimeController;
  final TextEditingController gracePeriodController;
  final TextEditingController noShowMultiplierController;
  final TextEditingController noShowThresholdController;
  final TextEditingController delayMinuteValueController;
  final TextEditingController downgradeValueController;

  final FocusNode baseValueFocus;
  final FocusNode delayToleranceFocus;
  final FocusNode noShowMultiplierFocus;
  final FocusNode delayMinuteValueFocus;
  final FocusNode downgradeValueFocus;
  final FocusNode earlyArrivalFocus;
  final FocusNode dwellTimeFocus;
  final FocusNode noShowThresholdFocus;
  final FocusNode gracePeriodFocus;

  final VoidCallback onContinue;

  void _applyTemplate(PenaltiesFormData p) {
    baseValueController.text = (p.baseTripValueCents / 100.0)
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    noShowMultiplierController.text = (p.noShowPenaltyBps / 10000.0)
        .toStringAsFixed(1)
        .replaceAll('.', ',');
    delayToleranceController.text = p.delayToleranceMinutes.toString();
    delayMinuteValueController.text = (p.delayPenaltyPerMinuteCents / 100.0)
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    downgradeValueController.text = (p.downgradePenaltyFlatCents / 100.0)
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    noShowThresholdController.text = p.noShowThresholdMinutes.toString();
    earlyArrivalToleranceController.text = p.earlyArrivalToleranceMinutes
        .toString();
    dwellTimeController.text = p.dwellTimeMinutes.toString();
    gracePeriodController.text = p.gracePeriodMinutes.toString();
  }

  Future<void> _saveAsTemplate(BuildContext context, WidgetRef ref) async {
    final orgId = ref.read(currentOrganizationIdProvider);
    if (orgId == null) return;
    final sessionId = ref.read(currentSessionIdProvider) ?? '';

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Salvar como Modelo'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome do Modelo',
              hintText: 'Ex: Fretamento Interurbano',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;

    try {
      final noShowMult =
          double.tryParse(
            noShowMultiplierController.text.replaceAll(',', '.'),
          ) ??
          1.5;
      final delayPerMin =
          ((double.tryParse(
                        delayMinuteValueController.text.replaceAll(',', '.'),
                      ) ??
                      0.5) *
                  100)
              .round();
      final downgrade =
          ((double.tryParse(
                        downgradeValueController.text.replaceAll(',', '.'),
                      ) ??
                      50) *
                  100)
              .round();

      final penalties = PenaltiesFormData(
        noShowPenaltyBps: (noShowMult * 10000).round(),
        delayToleranceMinutes:
            int.tryParse(delayToleranceController.text) ?? 15,
        delayPenaltyPerMinuteCents: delayPerMin,
        downgradePenaltyFlatCents: downgrade,
        noShowThresholdMinutes:
            int.tryParse(noShowThresholdController.text) ?? 60,
        earlyArrivalToleranceMinutes:
            int.tryParse(earlyArrivalToleranceController.text) ?? 5,
        dwellTimeMinutes: int.tryParse(dwellTimeController.text) ?? 3,
        gracePeriodMinutes: int.tryParse(gracePeriodController.text) ?? 0,
        baseTripValueCents:
            ((double.tryParse(baseValueController.text.replaceAll(',', '.')) ??
                        0) *
                    100)
                .round(),
      );

      await ref
          .read(saveSlaTemplateHandlerProvider)
          .handle(
            organizationId: orgId,
            sessionId: sessionId,
            name: name,
            penalties: penalties,
          );

      ref.invalidate(slaTemplatesProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Modelo "$name" salvo.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar modelo: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  void _showTemplatePicker(
    BuildContext context,
    AsyncValue<List<SlaTemplateView>> allTemplatesAsync,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxHeight: 500),
      builder: (ctx) => switch (allTemplatesAsync) {
        AsyncData(:final value) => () {
          final templates = value;
          if (templates.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Nenhum modelo disponível'),
              ),
            );
          }
          final presets = templates
              .where((t) => t.id.startsWith('preset:'))
              .toList();
          final orgTemplates = templates
              .where((t) => !t.id.startsWith('preset:'))
              .toList();

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (presets.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'MODELOS DO SISTEMA',
                    style: VeraProbTypography.badge.copyWith(
                      color: VeraProbColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ...presets.map(
                  (t) => TemplateTile(
                    template: t,
                    onTap: () {
                      _applyTemplate(t.penalties);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              ],
              if (orgTemplates.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'MEUS MODELOS',
                    style: VeraProbTypography.badge.copyWith(
                      color: VeraProbColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ...orgTemplates.map(
                  (t) => TemplateTile(
                    template: t,
                    onTap: () {
                      _applyTemplate(t.penalties);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              ],
            ],
          );
        }(),
        AsyncLoading() => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        AsyncError(:final error) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Erro ao carregar modelos: $error',
            style: const TextStyle(color: VeraProbColors.error),
          ),
        ),
      },
    );
  }

  Widget _buildTemplateHeader(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SlaTemplateView>> allTemplatesAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Acordo de penalidades e janelas operacionais para garantir o nível de serviço.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
        const SizedBox(height: VeraProbSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: DropdownButtonFormField<TransportVertical>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Vertical de Transporte',
                  prefixIcon: Icon(Icons.category_outlined, size: 20),
                  isDense: true,
                ),
                items: TransportVertical.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null || v == TransportVertical.custom) {
                    baseValueController.text = '';
                  } else {
                    _applyTemplate(SmartDefaultsService.defaultsFor(v));
                  }
                },
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.style, size: 16),
              label: const Text('Aplicar Modelo'),
              onPressed: () => _showTemplatePicker(context, allTemplatesAsync),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Salvar como Modelo'),
              onPressed: () => _saveAsTemplate(context, ref),
            ),
          ],
        ),
        const SizedBox(height: VeraProbSpacing.md),
        TextField(
          controller: baseValueController,
          focusNode: baseValueFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Valor Base por Viagem (R\$)',
            prefixText: r'R$ ',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) =>
              FocusScope.of(context).requestFocus(delayToleranceFocus),
        ),
      ],
    );
  }

  Widget _buildPunctualitySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          icon: Icons.schedule,
          label: 'Pontualidade e Janelas Operacionais',
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        TextField(
          controller: delayToleranceController,
          focusNode: delayToleranceFocus,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Tolerância de Atraso (min)',
            suffixText: ' min',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) =>
              FocusScope.of(context).requestFocus(gracePeriodFocus),
        ),
        const SizedBox(height: VeraProbSpacing.md),
        TextField(
          controller: gracePeriodController,
          focusNode: gracePeriodFocus,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Carência Pré-Avaliação (min)',
            suffixText: ' min',
            border: OutlineInputBorder(),
            isDense: true,
            helperText:
                'Janela de espera após o horário previsto antes de iniciar checagem.',
          ),
          onSubmitted: (_) =>
              FocusScope.of(context).requestFocus(noShowMultiplierFocus),
        ),
      ],
    );
  }

  Widget _buildCriticalFailuresSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          icon: Icons.warning_amber_rounded,
          label: 'Falhas Críticas (Cláusulas de Penalidade)',
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        TextField(
          controller: noShowMultiplierController,
          focusNode: noShowMultiplierFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Multiplicador No-Show',
            suffixText: ' x',
            border: OutlineInputBorder(),
            isDense: true,
            suffixIcon: InfoTooltip(
              message:
                  'Alavanca Financeira: penalidade aplicada ao valor base '
                  'da viagem em caso de No-Show.\n'
                  'Ex.: 1,5x = 150% do valor contratual cobrado do operador.',
            ),
          ),
          onSubmitted: (_) =>
              FocusScope.of(context).requestFocus(delayMinuteValueFocus),
        ),
      ],
    );
  }

  Widget _buildFleetQualitySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          icon: Icons.directions_bus,
          label: 'Qualidade da Frota',
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: delayMinuteValueController,
                focusNode: delayMinuteValueFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Multa por Minuto de Atraso',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(downgradeValueFocus),
              ),
            ),
            const SizedBox(width: VeraProbSpacing.sm),
            Expanded(
              child: TextField(
                controller: downgradeValueController,
                focusNode: downgradeValueFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Multa por Downgrade de Veículo',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => onContinue(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdvancedOptionsSection(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.tune),
      title: const Text('Opções Avançadas'),
      initiallyExpanded: false,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: VeraProbSpacing.md,
            right: VeraProbSpacing.md,
            bottom: VeraProbSpacing.md,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: earlyArrivalToleranceController,
                      focusNode: earlyArrivalFocus,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tolerância de Antecipação (min)',
                        suffixText: ' min',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(dwellTimeFocus),
                    ),
                  ),
                  const SizedBox(width: VeraProbSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: dwellTimeController,
                      focusNode: dwellTimeFocus,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tempo Mínimo de Permanência (min)',
                        suffixText: ' min',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => FocusScope.of(
                        context,
                      ).requestFocus(noShowThresholdFocus),
                    ),
                  ),
                  const SizedBox(width: VeraProbSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: noShowThresholdController,
                      focusNode: noShowThresholdFocus,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Teto para No-Show Automático (min)',
                        suffixText: ' min',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: InfoTooltip(
                          message:
                              'Atraso (em minutos) a partir do qual o sistema '
                              'classifica automaticamente a execução como No-Show. '
                              'Padrão de mercado: 60 min.',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTemplatesAsync = ref.watch(allTemplatesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTemplateHeader(context, ref, allTemplatesAsync),
        const SizedBox(height: VeraProbSpacing.lg),
        _buildPunctualitySection(context),
        const SizedBox(height: VeraProbSpacing.lg),
        _buildCriticalFailuresSection(context),
        const SizedBox(height: VeraProbSpacing.lg),
        _buildFleetQualitySection(context),
        const SizedBox(height: VeraProbSpacing.md),
        _buildAdvancedOptionsSection(context),
      ],
    );
  }
}
