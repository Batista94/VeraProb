import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:busflow/application/sla_audit/create_contract_command.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/state/providers/auth_providers.dart';
import 'package:busflow/state/providers/contract_providers.dart';

/// Dialog form for creating a new [Contract] in draft status.
///
/// Usage: `await CreateContractForm.show(context, ref)`
/// Returns `true` if contract was created successfully, `false` otherwise.
class CreateContractForm extends ConsumerStatefulWidget {
  const CreateContractForm({super.key});

  /// Opens the dialog and returns `true` on successful creation.
  static Future<bool?> show(BuildContext context, WidgetRef ref) {
    return showDialog<bool>(
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
    );
    if (picked == null) return;
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
      setState(
        () => _errorMessage = 'A data de fim deve ser posterior à data de início.',
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
      await handler.handle(
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

      if (mounted) Navigator.of(context).pop(true);
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.description_outlined),
                    const SizedBox(width: 10),
                    const Text(
                      'Novo Contrato',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(false),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Nome do contrato
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do contrato *',
                    hintText: 'Ex: Rota SP–Campinas 2026',
                  ),
                  maxLength: 100,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),

                // Nome do contratante
                TextFormField(
                  controller: _contractorController,
                  decoration: const InputDecoration(
                    labelText: 'Contratante *',
                    hintText: 'Nome da empresa contratante',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),

                // Descrição (opcional)
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição (opcional)',
                    hintText: 'Detalhes adicionais do contrato',
                  ),
                  maxLines: 2,
                  minLines: 2,
                ),
                const SizedBox(height: 16),

                // Vigência
                const Text(
                  'Período de Vigência *',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DatePickerField(
                        label: 'Início',
                        value: _validFrom,
                        onTap: () => _pickDate(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DatePickerField(
                        label: 'Fim',
                        value: _validUntil,
                        onTap: () => _pickDate(isStart: false),
                      ),
                    ),
                  ],
                ),

                // Error message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Criar Contrato'),
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

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
          isDense: true,
        ),
        child: Text(
          value != null
              ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
              : 'Selecionar',
          style: TextStyle(
            color: value != null ? null : Colors.grey.shade500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
