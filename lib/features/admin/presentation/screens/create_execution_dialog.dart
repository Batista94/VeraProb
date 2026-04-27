import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/admin/create_execution_command.dart';
import 'package:veraprob/presentation/widgets/skeleton_list_loader.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/assets_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';

/// Modal dialog for OCC operators to create a new planned Execution (trip).
/// Calls the create_execution_for_operator RPC — no direct DB write.
/// INV-1: org_id from JWT, not user input.
/// INV-6: window dates passed as UTC.
/// INV-15: RPC is idempotent (ON CONFLICT set_id DO NOTHING).
class CreateExecutionDialog extends ConsumerStatefulWidget {
  const CreateExecutionDialog({super.key});

  @override
  ConsumerState<CreateExecutionDialog> createState() =>
      _CreateExecutionDialogState();
}

class _CreateExecutionDialogState extends ConsumerState<CreateExecutionDialog> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedDriverId;
  String? _selectedContractId;
  String? _selectedOriginZoneId;
  String? _selectedDestinationZoneId;

  DateTime _windowStart = DateTime.now().toUtc(); // INV-6: UTC
  DateTime _windowEnd = DateTime.now().toUtc().add(const Duration(hours: 8));

  bool _isSaving = false;
  String? _resultSetId;

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(driverListProvider);
    final contractsAsync = ref.watch(contractListProvider);
    final zonesAsync = ref.watch(operationalZonesProvider);

    final isLoading =
        driversAsync.isLoading ||
        contractsAsync.isLoading ||
        zonesAsync.isLoading;

    return Dialog(
      backgroundColor: VeraProbColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.add_road_outlined,
                    size: 24,
                    color: VeraProbColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Text('Nova Viagem', style: VeraProbTypography.sectionTitle),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Crie uma execução planejada sem acesso direto ao banco de dados.',
                style: VeraProbTypography.bodyMedium.copyWith(
                  color: VeraProbColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Divider(height: 24),
              if (_resultSetId != null)
                _SuccessCard(setId: _resultSetId!)
              else if (isLoading)
                const SkeletonListLoader(itemCount: 4)
              else
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Contract ──────────────────────────────────────
                          const _SectionLabel('Contrato'),
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Contrato *',
                              prefixIcon: Icon(
                                Icons.description_outlined,
                                size: 18,
                              ),
                            ),
                            initialValue: _selectedContractId,
                            items:
                                contractsAsync.value
                                    ?.map(
                                      (c) => DropdownMenuItem(
                                        value: c.id,
                                        child: Text(
                                          '${c.name} — ${c.contractorName}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList() ??
                                [],
                            onChanged: (v) =>
                                setState(() => _selectedContractId = v),
                            validator: (v) =>
                                v == null ? 'Selecione um contrato' : null,
                          ),
                          const SizedBox(height: 16),

                          // ── Driver ────────────────────────────────────────
                          const _SectionLabel('Motorista'),
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Motorista *',
                              prefixIcon: Icon(Icons.person_outline, size: 18),
                            ),
                            initialValue: _selectedDriverId,
                            items:
                                driversAsync.value
                                    ?.map(
                                      (d) => DropdownMenuItem(
                                        value: d.id,
                                        child: Text(
                                          d.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList() ??
                                [],
                            onChanged: (v) =>
                                setState(() => _selectedDriverId = v),
                            validator: (v) =>
                                v == null ? 'Selecione um motorista' : null,
                          ),
                          const SizedBox(height: 16),

                          // ── Zones ─────────────────────────────────────────
                          const _SectionLabel('Zonas Operacionais'),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  decoration: const InputDecoration(
                                    labelText: 'Origem',
                                    prefixIcon: Icon(
                                      Icons.location_on_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  initialValue: _selectedOriginZoneId,
                                  items:
                                      zonesAsync.value
                                          ?.map(
                                            (z) => DropdownMenuItem(
                                              value: z.id,
                                              child: Text(
                                                z.name,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList() ??
                                      [],
                                  onChanged: (v) =>
                                      setState(() => _selectedOriginZoneId = v),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  decoration: const InputDecoration(
                                    labelText: 'Destino',
                                    prefixIcon: Icon(
                                      Icons.flag_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  initialValue: _selectedDestinationZoneId,
                                  items:
                                      zonesAsync.value
                                          ?.map(
                                            (z) => DropdownMenuItem(
                                              value: z.id,
                                              child: Text(
                                                z.name,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList() ??
                                      [],
                                  onChanged: (v) => setState(
                                    () => _selectedDestinationZoneId = v,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── Window ────────────────────────────────────────
                          const _SectionLabel('Janela de Tempo (UTC)'),
                          Row(
                            children: [
                              Expanded(
                                child: _DateTimeButton(
                                  label: 'Início',
                                  value: _windowStart,
                                  onPick: (dt) =>
                                      setState(() => _windowStart = dt),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _DateTimeButton(
                                  label: 'Fim',
                                  value: _windowEnd,
                                  onPick: (dt) =>
                                      setState(() => _windowEnd = dt),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── Submit ────────────────────────────────────────
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: FilledButton.icon(
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_outlined),
                              label: Text(
                                _isSaving ? 'Criando...' : 'Criar Viagem',
                              ),
                              onPressed: _isSaving ? null : _submit,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      if (orgId == null) {
        throw StateError('org_id not found in session — INV-1');
      }
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      final setId = await ref
          .read(createExecutionHandlerProvider)
          .handle(
            CreateExecutionCommand(
              organizationId: orgId,
              sessionId: sessionId,
              contractId: _selectedContractId!,
              driverId: _selectedDriverId!,
              originZoneId: _selectedOriginZoneId,
              destinationZoneId: _selectedDestinationZoneId,
              windowStartUtc: _windowStart.toUtc(),
              windowEndUtc: _windowEnd.toUtc(),
            ),
          );

      setState(() => _resultSetId = setId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar viagem: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: VeraProbColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DateTimeButton extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;

  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.schedule_outlined, size: 14),
      label: Text(
        '$label\n${_fmt(value)}',
        style: const TextStyle(fontSize: 11),
        textAlign: TextAlign.center,
      ),
      onPressed: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().toUtc().add(const Duration(days: 30)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (time == null) return;
        // INV-6: construct as UTC
        onPick(
          DateTime.utc(date.year, date.month, date.day, time.hour, time.minute),
        );
      },
    );
  }

  String _fmt(DateTime dt) {
    final u = dt.toUtc();
    return '${u.day.toString().padLeft(2, '0')}/${u.month.toString().padLeft(2, '0')} '
        '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')} UTC';
  }
}

class _SuccessCard extends StatelessWidget {
  final String setId;
  const _SuccessCard({required this.setId});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        const Icon(
          Icons.check_circle_outline,
          color: VeraProbColors.success,
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(
          'Viagem criada com sucesso!',
          style: VeraProbTypography.sectionTitle,
        ),
        const SizedBox(height: 8),
        SelectableText(
          setId,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: VeraProbColors.primary,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
