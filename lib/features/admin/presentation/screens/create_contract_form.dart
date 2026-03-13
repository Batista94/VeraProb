import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pactaflow/application/sla_audit/create_contract_command.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';
import 'package:pactaflow/state/providers/auth_providers.dart';
import 'package:pactaflow/state/providers/contract_providers.dart';
import 'package:pactaflow/core/theme/app_theme.dart';

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
  final _contractorController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime? _validFrom;
  DateTime? _validUntil;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Clear error message when user starts typing or changing fields
    _nameController.addListener(_clearError);
    _contractorController.addListener(_clearError);
    _descriptionController.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contractorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? (_validFrom ?? DateTime.now()) : (_validUntil ?? DateTime.now());
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
        _validUntil = DateTime.utc(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_validFrom == null || _validUntil == null) {
      setState(() => _errorMessage = 'Selecione as datas de vigência.');
      return;
    }
    if (!_validUntil!.isAfter(_validFrom!)) {
      setState(() => _errorMessage = 'A data de fim deve ser posterior à data de início.');
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
      final contract = await handler.handle(
        CreateContractCommand(
          organizationId: organizationId,
          name: _nameController.text.trim(),
          contractorName: _contractorController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          validFromUtc: _validFrom!,
          validUntilUtc: _validUntil!,
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
                      child: const Icon(Icons.description_rounded, color: PactaFlowColors.primary, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Novo Contrato Operacional',
                      style: PactaFlowTypography.sectionTitle.copyWith(fontSize: 20),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: PactaFlowColors.textDisabled),
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Registre os parâmetros regulatórios para auditoria de SLR.',
                  style: PactaFlowTypography.bodySmall,
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
                      border: Border.all(color: PactaFlowColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: PactaFlowColors.error, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Sessão sem organização vinculada. Faça logout e login novamente.',
                            style: PactaFlowTypography.bodySmall.copyWith(color: PactaFlowColors.error),
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
                    labelText: 'Identificação Tributária/Comercial *',
                    hintText: 'Ex: Concessão Norte - Lote 1',
                  ),
                  maxLength: 100,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _contractorController,
                  style: PactaFlowTypography.bodyMedium,
                  decoration: const InputDecoration(
                    labelText: 'Entidade Contratante (Auditor) *',
                    hintText: 'Ex: SPTRANS / Secretaria de Transportes',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
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

                if (_errorMessage != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PactaFlowColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: PactaFlowColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: PactaFlowColors.error, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: PactaFlowColors.error, fontSize: 13, fontWeight: FontWeight.w500),
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
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(null),
                      child: Text('DESCARTAR', style: PactaFlowTypography.badge.copyWith(color: PactaFlowColors.textSecondary)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('ATIVAR CONTRATO'),
                    ),
                  ],
                ),
              ],
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

  const _DatePickerField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: PactaFlowColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PactaFlowColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: PactaFlowTypography.kpiLabel.copyWith(fontSize: 10)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value != null
                        ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
                        : 'Definir Data',
                    style: PactaFlowTypography.bodyMedium.copyWith(
                      color: value != null ? PactaFlowColors.textPrimary : PactaFlowColors.textDisabled,
                      fontWeight: value != null ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today_rounded, size: 14, color: PactaFlowColors.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
