import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:pactaflow/application/sla_audit/create_contract_command.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';
import 'package:pactaflow/state/providers/auth_providers.dart';
import 'package:pactaflow/state/providers/contract_providers.dart';
import 'package:pactaflow/state/providers/contractor_providers.dart';
import 'package:pactaflow/domain/sla_audit/contractor.dart';
import 'package:pactaflow/core/theme/app_theme.dart';
import '../widgets/contractor_type_ahead_field.dart';

class CreateContractForm extends ConsumerStatefulWidget {
  const CreateContractForm({super.key});

  static Future<String?> show(BuildContext context, WidgetRef ref) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateContractForm(),
    );
  }

  @override
  ConsumerState<CreateContractForm> createState() => _CreateContractFormState();
}

class _CreateContractFormState extends ConsumerState<CreateContractForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _financialCeilingController = TextEditingController();

  Contractor? _selectedContractor;
  DateTime? _validFrom;
  DateTime? _validUntil;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_clearError);
    _descriptionController.addListener(_clearError);
    _financialCeilingController.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _financialCeilingController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_validFrom ?? DateTime.now())
        : (_validUntil ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: PactaFlowColors.primary,
              onPrimary: Colors.white,
              surface: PactaFlowColors.surfaceElevated,
              onSurface: PactaFlowColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    _clearError();
    setState(() {
      if (isStart) {
        _validFrom = DateTime.utc(picked.year, picked.month, picked.day);
      } else {
        _validUntil = DateTime.utc(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_validFrom == null || _validUntil == null) {
      setState(() => _errorMessage = 'Selecione as datas de vigência.');
      return;
    }

    if (_selectedContractor == null) {
      setState(() => _errorMessage = 'Selecione ou crie um contratante.');
      return;
    }

    if (!_validUntil!.isAfter(_validFrom!)) {
      setState(
        () => _errorMessage =
            'A data de fim deve ser posterior à data de início.',
      );
      return;
    }

    final organizationId = ref.read(currentOrganizationIdProvider);
    if (organizationId == null) {
      setState(() => _errorMessage = 'Sessão inválida. Faça login novamente.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final handler = ref.read(createContractHandlerProvider);
      final rawCeiling = _financialCeilingController.text.trim();
      
      final cleanValue = rawCeiling.replaceAll('.', '').replaceAll(',', '');
      final financialCeilingCents = cleanValue.isEmpty ? null : int.tryParse(cleanValue);

      final contract = await handler.handle(
        CreateContractCommand(
          organizationId: organizationId,
          name: _nameController.text.trim(),
          contractorName: _selectedContractor!.name,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          validFromUtc: _validFrom!,
          validUntilUtc: _validUntil!,
          financialCeilingCents: financialCeilingCents,
        ),
      );

      if (mounted) Navigator.of(context).pop(contract.id);
    } on DomainException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final organizationId = ref.watch(currentOrganizationIdProvider);
    final isFetchingOrg = ref.watch(organizationIdFetcherProvider).isLoading;

    return Dialog(
      backgroundColor: PactaFlowColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: PactaFlowColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: PactaFlowColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.description_rounded,
                          color: PactaFlowColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Novo Contrato Operacional',
                        style: PactaFlowTypography.sectionTitle.copyWith(
                          fontSize: 20,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: PactaFlowColors.textDisabled,
                        ),
                        onPressed: () => Navigator.of(context).pop(null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Registre os parâmetros regulatórios para auditoria de SLR.',
                    style: PactaFlowTypography.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: PactaFlowColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: PactaFlowColors.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 15,
                          color: PactaFlowColors.primary.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Após criar o contrato, declare o Plano Operacional para vincular templates SLA e turnos.',
                            style: PactaFlowTypography.bodySmall.copyWith(
                              color: PactaFlowColors.primary.withValues(
                                alpha: 0.9,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isFetchingOrg)
                    const LinearProgressIndicator()
                  else if (organizationId == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PactaFlowColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: PactaFlowColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: PactaFlowColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Sessão sem organização vinculada. Faça logout e login novamente.',
                              style: PactaFlowTypography.bodySmall.copyWith(
                                color: PactaFlowColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _nameController,
                    style: PactaFlowTypography.bodyMedium,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Contrato *',
                      hintText: 'Ex: Concessão Norte - Lote 1',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    maxLength: 100,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Campo obrigatório'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  Consumer(
                    builder: (context, ref, child) {
                      final contractorsAsync = ref.watch(contractorListProvider);
                      final contractors = contractorsAsync.valueOrNull ?? [];
                      
                      return ContractorTypeAheadField(
                        label: 'Entidade Contratante (Auditor) *',
                        prefixIcon: Icons.handshake_outlined,
                        contractors: contractors,
                        selectedContractor: _selectedContractor,
                        onInvalidateContractors: () async {
                          ref.invalidate(contractorListProvider);
                          await ref.read(contractorListProvider.future);
                        },
                        onChanged: (c) {
                          setState(() {
                            _selectedContractor = c;
                            if (c != null) _clearError();
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'CRONOGRAMA DE VIGÊNCIA',
                    style: PactaFlowTypography.kpiLabel,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DatePickerField(
                          label: 'Início',
                          value: _validFrom,
                          onTap: () => _pickDate(isStart: true),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _DatePickerField(
                          label: 'Término',
                          value: _validUntil,
                          onTap: () => _pickDate(isStart: false),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'PROTEÇÃO FINANCEIRA',
                    style: PactaFlowTypography.kpiLabel,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _financialCeilingController,
                    style: PactaFlowTypography.bodyMedium,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Teto Financeiro (opcional)',
                      hintText: '0,00',
                      prefixText: 'R\$ ',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      helperText:
                          'Limite máximo de penalidades acumuladas. Habilita o KPI Risco Relativo.',
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PactaFlowColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: PactaFlowColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: PactaFlowColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: PactaFlowColors.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(null),
                        child: Text(
                          'DESCARTAR',
                          style: PactaFlowTypography.badge.copyWith(
                            color: PactaFlowColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('ATIVAR CONTRATO'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: PactaFlowTypography.bodyMedium.copyWith(color: PactaFlowColors.textSecondary),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: const Icon(Icons.calendar_month_rounded, color: PactaFlowColors.primary, size: 20),
        ),
        isEmpty: false,
        child: Text(
          value != null
              ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
              : 'Selecionar $label...',
          style: PactaFlowTypography.bodyMedium.copyWith(
            color: value != null ? PactaFlowColors.textPrimary : PactaFlowColors.textSecondary,
            fontWeight: value != null ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    double value = double.parse(newValue.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final formatter = NumberFormat.currency(locale: 'pt_BR', symbol: '');
    String newText = formatter.format(value / 100).trim();

    return newValue.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length));
  }
}
