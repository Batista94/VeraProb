import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/core/utils/cnpj_input_formatter.dart';
import 'package:veraprob/core/utils/cnpj_validator.dart';
import 'package:veraprob/application/shared/app_types.dart';


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
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
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
          if (cnpjApiError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12),
              child: Text(
                cnpjApiError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
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
        ],
      ),
    );
  }
}

// ── Step 2: Limits ─────────────────────────────────────────────────────────────

class Step2Limits extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController maxVehiclesCtrl;
  final TextEditingController maxContractsCtrl;
  final String tradeName;
  final String planLabel;

  const Step2Limits({
    super.key,
    required this.formKey,
    required this.maxVehiclesCtrl,
    required this.maxContractsCtrl,
    required this.tradeName,
    required this.planLabel,
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
        ],
      ),
    );
  }
}

// ── Step 3: Admin Invite ───────────────────────────────────────────────────────

class Step3AdminInvite extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController adminEmailCtrl;
  final String tradeName;
  final String planLabel;
  final String maxVehicles;
  final String maxContracts;
  final bool isSubmitting;

  const Step3AdminInvite({
    super.key,
    required this.formKey,
    required this.adminEmailCtrl,
    required this.tradeName,
    required this.planLabel,
    required this.maxVehicles,
    required this.maxContracts,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
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
                  value: tradeName,
                ),
                WizardSummaryRow(
                  icon: Icons.star_outline,
                  label: 'Plano',
                  value: planLabel,
                ),
                WizardSummaryRow(
                  icon: Icons.directions_car,
                  label: 'Máx. Veículos',
                  value: maxVehicles,
                ),
                WizardSummaryRow(
                  icon: Icons.description_outlined,
                  label: 'Máx. Contratos',
                  value: maxContracts,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: adminEmailCtrl,
            decoration: const InputDecoration(
              labelText: 'E-mail do Admin Inicial *',
              hintText: 'admin@empresa.com.br',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              if (!v.trim().contains('@')) return 'E-mail inválido';
              return null;
            },
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
                  'Um convite válido por 7 dias será enviado para este e-mail com permissão de Administrador.',
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
