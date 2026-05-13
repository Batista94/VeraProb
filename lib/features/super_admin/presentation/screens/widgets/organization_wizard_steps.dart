import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/formatters/brl_currency_input_formatter.dart';
import 'package:veraprob/presentation/shared/formatters/cnpj_input_formatter.dart';
import 'package:veraprob/domain/shared/cnpj_validator.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/super_admin/org_preset_view_model.dart';
import 'package:veraprob/presentation/shared/widgets/info_tooltip.dart';

const kBrTimezones = [
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Belem',
  'America/Fortaleza',
  'America/Recife',
  'America/Noronha',
  'America/Cuiaba',
  'America/Porto_Velho',
  'America/Rio_Branco',
  'America/Boa_Vista',
];

const kCurrencies = ['BRL', 'USD', 'EUR'];

// ── Step 1: Fiscal Data ────────────────────────────────────────────────────────

class Step1FiscalData extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController legalNameCtrl;
  final TextEditingController tradeNameCtrl;
  final TextEditingController cnpjCtrl;
  final PlanType selectedPlan;
  final String timezone;
  final String currency;
  final String? cnpjApiError;
  final bool cnpjChecking;
  final bool cnpjAutoFilled;
  final bool cnpjAutoInactive;
  final ValueChanged<PlanType> onPlanChanged;
  final ValueChanged<String> onTimezoneChanged;
  final ValueChanged<String> onCurrencyChanged;

  // Optional billing / integration fields
  final TextEditingController? contactEmailCtrl;
  final TextEditingController? externalIdCtrl;
  final TextEditingController? billingDayCtrl;

  const Step1FiscalData({
    super.key,
    required this.formKey,
    required this.legalNameCtrl,
    required this.tradeNameCtrl,
    required this.cnpjCtrl,
    required this.selectedPlan,
    required this.timezone,
    required this.currency,
    required this.cnpjApiError,
    required this.cnpjChecking,
    required this.cnpjAutoFilled,
    required this.cnpjAutoInactive,
    required this.onPlanChanged,
    required this.onTimezoneChanged,
    required this.onCurrencyChanged,
    this.contactEmailCtrl,
    this.externalIdCtrl,
    this.billingDayCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const ValueKey('field_legal_name'),
            controller: legalNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Razão Social *',
              hintText: 'Ex: Transportes Silva Ltda.',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('field_trade_name'),
            controller: tradeNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome Fantasia *',
              hintText: 'Ex: Silva Logística',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: cnpjCtrl,
            decoration: InputDecoration(
              labelText: 'CNPJ *',
              hintText: '00.000.000/0000-00',
              errorText: cnpjApiError,
              suffixIcon: cnpjChecking
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : cnpjApiError != null
                  ? const Icon(Icons.error_outline, color: VeraProbColors.error)
                  : null,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              CnpjInputFormatter(),
            ],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              final digits = v.replaceAll(RegExp(r'\D'), '');
              if (digits.length != 14) return 'CNPJ deve ter 14 dígitos';
              if (!CnpjValidator.isValid(digits)) return 'CNPJ inválido';
              return null;
            },
          ),
          if (cnpjAutoFilled && cnpjApiError == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: VeraProbColors.success,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Dados preenchidos via ReceitaWS',
                        style: TextStyle(
                          fontSize: 12,
                          color: VeraProbColors.success,
                        ),
                      ),
                    ],
                  ),
                  if (cnpjAutoInactive)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 14,
                          color: VeraProbColors.warning,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Empresa inativa na Receita Federal',
                          style: TextStyle(
                            fontSize: 12,
                            color: VeraProbColors.warning,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text('Plano *', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SegmentedButton<PlanType>(
            segments: PlanType.values
                .map((p) => ButtonSegment(value: p, label: Text(p.label)))
                .toList(),
            selected: {selectedPlan},
            onSelectionChanged: (s) => onPlanChanged(s.first),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: timezone,
            decoration: const InputDecoration(labelText: 'Fuso Horário *'),
            items: kBrTimezones
                .map((tz) => DropdownMenuItem(value: tz, child: Text(tz)))
                .toList(),
            onChanged: (v) => onTimezoneChanged(v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: currency,
            decoration: const InputDecoration(labelText: 'Moeda *'),
            items: kCurrencies
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => onCurrencyChanged(v!),
          ),
          if (contactEmailCtrl != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('field_contact_email'),
              controller: contactEmailCtrl,
              decoration: const InputDecoration(
                labelText: 'E-mail de Cobrança',
                hintText: 'financeiro@empresa.com.br',
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (!v.trim().contains('@')) return 'E-mail inválido';
                return null;
              },
            ),
          ],
          if (externalIdCtrl != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('field_external_id'),
              controller: externalIdCtrl,
              decoration: const InputDecoration(
                labelText: 'ID Externo (CRM/ERP)',
                hintText: 'Ex: CRM-00123',
              ),
              maxLength: 100,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (v.trim().length > 100) return 'Máximo 100 caracteres';
                return null;
              },
            ),
          ],
          if (billingDayCtrl != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('field_billing_day'),
              controller: billingDayCtrl,
              decoration: const InputDecoration(
                labelText: 'Dia de Faturamento (1–28)',
                hintText: 'Ex: 5',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final day = int.tryParse(v.trim());
                if (day == null || day < 1 || day > 28) {
                  return 'Deve ser entre 1 e 28';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ── Step 2: Limits + Operational Config ───────────────────────────────────────

class Step2Limits extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController maxVehiclesCtrl;
  final TextEditingController maxContractsCtrl;
  final TextEditingController toolCostCtrl;
  final TextEditingController reasonCtrl;
  final String tradeName;
  final String planLabel;
  final String? selectedPreset;

  /// Capabilities as a presentation-safe ViewModel.
  /// This widget never imports [OrgCapabilities] from domain.
  final OrgCapabilitiesViewModel capabilities;

  final int dwellTimeSeconds;
  final ValueChanged<String?> onPresetChanged;
  final ValueChanged<int> onDwellChanged;

  /// Called when a capability flag is toggled by the SuperAdmin.
  /// Key is the capability identifier (e.g. 'allows_sealing').
  final void Function(String key, bool value) onCapabilityToggled;

  /// Called when the kinematic speed slider changes.
  final ValueChanged<double> onSpeedChanged;

  const Step2Limits({
    super.key,
    required this.formKey,
    required this.maxVehiclesCtrl,
    required this.maxContractsCtrl,
    required this.toolCostCtrl,
    required this.reasonCtrl,
    required this.tradeName,
    required this.planLabel,
    this.selectedPreset,
    required this.capabilities,
    required this.dwellTimeSeconds,
    required this.onPresetChanged,
    required this.onDwellChanged,
    required this.onCapabilityToggled,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tradeName.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VeraProbColors.superAdminSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(
                    Icons.business,
                    size: 16,
                    color: VeraProbColors.secondary,
                  ),
                  Text(
                    '$tradeName — Plano $planLabel',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('field_max_vehicles'),
            controller: maxVehiclesCtrl,
            decoration: const InputDecoration(
              labelText: 'Máximo de Veículos *',
              hintText: 'Ex: 50',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              final n = int.tryParse(v);
              if (n == null || n < 1) return 'Deve ser >= 1';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('field_max_contracts'),
            controller: maxContractsCtrl,
            decoration: const InputDecoration(
              labelText: 'Máximo de Contratos Ativos *',
              hintText: 'Ex: 10',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              final n = int.tryParse(v);
              if (n == null || n < 1) return 'Deve ser >= 1';
              return null;
            },
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          // ── Tipo de Operação (Template Disparador) ─────────────────────────
          Text(
            'Tipo de Operação',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Selecione um preset para pré-configurar os módulos abaixo. '
            'Todos os campos permanecem editáveis.',
            style: TextStyle(fontSize: 12, color: VeraProbColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: OrgPresetViewModel.labels.entries
                .map(
                  (e) =>
                      ButtonSegment<String>(value: e.key, label: Text(e.value)),
                )
                .toList(),
            selected: selectedPreset != null ? {selectedPreset!} : {},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) =>
                onPresetChanged(s.isEmpty ? null : s.first),
          ),

          // ── Banner de preset aplicado ──────────────────────────────────────
          if (selectedPreset != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: VeraProbColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: VeraProbColors.warning.withValues(alpha: 0.5),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tune, size: 15, color: VeraProbColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Preset aplicado. Você pode customizar os módulos abaixo '
                      'conforme o contrato específico.',
                      style: TextStyle(
                        fontSize: 12,
                        color: VeraProbColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Módulos operacionais (FilterChips editáveis) ───────────────────
          const SizedBox(height: 16),
          Text(
            'Módulos Operacionais',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          OrgCapabilitiesEditor(
            capabilities: capabilities,
            onToggled: onCapabilityToggled,
          ),

          const SizedBox(height: 20),
          TextFormField(
            controller: toolCostCtrl,
            decoration: const InputDecoration(
              labelText: 'Custo Mensal da Ferramenta *',
              hintText: 'R\$ 0,00',
              suffixIcon: InfoTooltip(
                message:
                    'Este valor é o divisor base para o cálculo do ROI Guardian no dashboard do cliente.',
                variant: InfoTooltipVariant.info,
              ),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [BrlCurrencyInputFormatter()],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              final cents = BrlCurrencyInputFormatter.toCents(v);
              if (cents == null) return 'Valor inválido';
              return null;
            },
          ),

          // ── Tempo de Parada Inicial (Padrão) ──────────────────────────────
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Tempo de Parada Inicial (Padrão)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 6),
              const InfoTooltip(
                message:
                    'Valor inicial padrão para fechamento automático de parada. '
                    'O Admin da Org poderá alterar este valor após o onboarding '
                    'nas configurações de negócio.',
                variant: InfoTooltipVariant.info,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${dwellTimeSeconds}s (~${(dwellTimeSeconds / 60).round()} min)',
            style: const TextStyle(
              fontSize: 13,
              color: VeraProbColors.textSecondary,
            ),
          ),
          SliderTheme(
            data: const SliderThemeData(
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 2,
              activeTrackColor: VeraProbColors.secondary,
              inactiveTrackColor: VeraProbColors.border,
              thumbColor: VeraProbColors.secondary,
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

          // ── Velocidade Máx. Inicial (Padrão) — sempre visível ─────────────
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Velocidade Máx. Inicial (Padrão)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 6),
              const InfoTooltip(
                message:
                    'Limite de velocidade que gera alerta no monitor. '
                    'O Admin da Org poderá ajustar este valor nas configurações '
                    'de negócio após o onboarding.',
                variant: InfoTooltipVariant.info,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            capabilities.maxKinematicSpeedKmh != null
                ? '${capabilities.maxKinematicSpeedKmh!.toStringAsFixed(0)} km/h'
                : '—  (sem limite configurado)',
            style: const TextStyle(
              fontSize: 13,
              color: VeraProbColors.textSecondary,
            ),
          ),
          SliderTheme(
            data: const SliderThemeData(
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 2,
              activeTrackColor: VeraProbColors.secondary,
              inactiveTrackColor: VeraProbColors.border,
              thumbColor: VeraProbColors.secondary,
            ),
            child: Slider(
              value: (capabilities.maxKinematicSpeedKmh ?? 80.0).clamp(
                10.0,
                200.0,
              ),
              min: 10,
              max: 200,
              divisions: 38,
              label:
                  '${(capabilities.maxKinematicSpeedKmh ?? 80.0).toStringAsFixed(0)} km/h',
              onChanged: (v) => onSpeedChanged(v),
            ),
          ),

          // ── Justificativa (obrigatória em todo cadastro) ───────────────────
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Justificativa *',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Obrigatória para rastreabilidade no log de auditoria.',
            style: TextStyle(fontSize: 12, color: VeraProbColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText:
                  'Ex: Criação de novo tenant conforme contrato comercial #123',
              alignLabelWithHint: true,
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
        ],
      ),
    );
  }
}

// ── OrgCapabilitiesEditor (FilterChips interativos) ───────────────────────────

/// Renders capability flags from an [OrgCapabilitiesViewModel] as interactive
/// [FilterChip] widgets. The SuperAdmin can toggle any flag freely — the preset
/// acts as a template, not a blocking state.
///
/// **INV-4 / Lens 2:** This widget only knows about [OrgCapabilitiesViewModel]
/// (application layer) — never about [OrgCapabilities] (domain).
class OrgCapabilitiesEditor extends StatelessWidget {
  const OrgCapabilitiesEditor({
    super.key,
    required this.capabilities,
    required this.onToggled,
  });

  /// Presentation-safe capabilities ViewModel. No domain type here.
  final OrgCapabilitiesViewModel capabilities;

  /// Called when a capability is toggled. [key] maps to the capability name
  /// (e.g. 'allows_sealing') and [value] is the new boolean state.
  final void Function(String key, bool value) onToggled;

  @override
  Widget build(BuildContext context) {
    final chips = <_EditorChip>[
      _EditorChip(
        'Lacre',
        'allows_sealing',
        capabilities.allowsSealing,
        Icons.lock_outline,
      ),
      _EditorChip(
        'Carregamento',
        'allows_loading',
        capabilities.allowsLoading,
        Icons.inventory_2_outlined,
      ),
      _EditorChip(
        'Cargo Check',
        'allows_cargo_check',
        capabilities.allowsCargoCheck,
        Icons.fact_check_outlined,
      ),
      _EditorChip(
        'Incidente',
        'allows_incident',
        capabilities.allowsIncident,
        Icons.warning_amber_outlined,
      ),
      _EditorChip(
        'Doc',
        'allows_doc',
        capabilities.allowsDoc,
        Icons.description_outlined,
      ),
      _EditorChip(
        'Smart Classify',
        'smart_classify',
        capabilities.smartClassify,
        Icons.auto_awesome_outlined,
      ),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips.map((c) {
        return FilterChip(
          avatar: Icon(
            c.icon,
            size: 14,
            color: c.enabled
                ? VeraProbColors.success
                : VeraProbColors.textDisabled,
          ),
          label: Text(
            c.label,
            style: TextStyle(
              fontSize: 11,
              color: c.enabled
                  ? VeraProbColors.textPrimary
                  : VeraProbColors.textDisabled,
            ),
          ),
          selected: c.enabled,
          onSelected: (v) => onToggled(c.key, v),
          selectedColor: VeraProbColors.success.withValues(alpha: 0.1),
          backgroundColor: VeraProbColors.border.withValues(alpha: 0.3),
          checkmarkColor: VeraProbColors.success,
          side: BorderSide(
            color: c.enabled
                ? VeraProbColors.success.withValues(alpha: 0.4)
                : VeraProbColors.border,
            width: 0.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          showCheckmark: true,
        );
      }).toList(),
    );
  }
}

class _EditorChip {
  const _EditorChip(this.label, this.key, this.enabled, this.icon);
  final String label;
  final String key;
  final bool enabled;
  final IconData icon;
}

// ── Step 3: Admin Invite ───────────────────────────────────────────────────────

class Step3AdminInvite extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final List<String> adminEmails;
  final ValueChanged<List<String>> onEmailsChanged;
  final String tradeName;
  final String planLabel;
  final String maxVehicles;
  final String maxContracts;
  final bool isSubmitting;
  final TextEditingController emailCtrl;

  const Step3AdminInvite({
    super.key,
    required this.formKey,
    required this.adminEmails,
    required this.onEmailsChanged,
    required this.tradeName,
    required this.planLabel,
    required this.maxVehicles,
    required this.maxContracts,
    required this.isSubmitting,
    required this.emailCtrl,
  });

  @override
  State<Step3AdminInvite> createState() => _Step3AdminInviteState();
}

class _Step3AdminInviteState extends State<Step3AdminInvite> {
  String? _inputError;

  @override
  void dispose() {
    super.dispose();
  }

  void _addEmail(String raw) {
    final email = raw.trim().toLowerCase();
    if (email.isEmpty) return;
    if (!email.contains('@')) {
      setState(() => _inputError = 'E-mail invalido');
      return;
    }
    if (widget.adminEmails.contains(email)) {
      setState(() => _inputError = 'E-mail duplicado');
      return;
    }
    widget.onEmailsChanged([...widget.adminEmails, email]);
    widget.emailCtrl.clear();
    setState(() => _inputError = null);
  }

  void _removeEmail(String email) {
    widget.onEmailsChanged(
      widget.adminEmails.where((e) => e != email).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VeraProbColors.superAdminSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WizardSummaryRow(
                  icon: Icons.business,
                  label: 'Empresa',
                  value: widget.tradeName,
                ),
                WizardSummaryRow(
                  icon: Icons.star_outline,
                  label: 'Plano',
                  value: widget.planLabel,
                ),
                WizardSummaryRow(
                  icon: Icons.directions_car,
                  label: 'Max. Veiculos',
                  value: widget.maxVehicles,
                ),
                WizardSummaryRow(
                  icon: Icons.description_outlined,
                  label: 'Max. Contratos',
                  value: widget.maxContracts,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (widget.adminEmails.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.adminEmails
                  .map(
                    (email) => InputChip(
                      label: Text(email, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => _removeEmail(email),
                      deleteIconColor: VeraProbColors.error,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: widget.emailCtrl,
            decoration: InputDecoration(
              labelText: 'E-mails dos Admins *',
              hintText: 'Digite e pressione Enter ou clique em +',
              prefixIcon: const Icon(Icons.email_outlined),
              errorText: _inputError,
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _addEmail(widget.emailCtrl.text),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            onSubmitted: _addEmail,
          ),
          if (widget.adminEmails.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 12),
              child: Text(
                'Adicione pelo menos um e-mail.',
                style: TextStyle(fontSize: 12, color: VeraProbColors.error),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VeraProbColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: VeraProbColors.warning.withValues(alpha: 0.5),
              ),
            ),
            child: const Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: VeraProbColors.warning,
                ),
                Text(
                  'Convites validos por 7 dias serao enviados para cada e-mail com permissao de Administrador.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WizardSummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const WizardSummaryRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: VeraProbColors.secondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(color: VeraProbColors.textSecondary),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
