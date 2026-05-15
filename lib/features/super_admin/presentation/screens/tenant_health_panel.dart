import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/formatters/brl_currency_input_formatter.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/super_admin/org_preset_view_model.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/update_quota_form_data.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_list_panel.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_detail_panel.dart';
import 'package:veraprob/features/super_admin/presentation/screens/widgets/organization_wizard_steps.dart';
import 'package:veraprob/presentation/shared/ui/info_tooltip.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';

/// Cross-tenant health dashboard for SuperAdmin.
///
/// Stage H: Split-view layout with TenantListPanel (320px) + TenantDetailPanel.
///
/// **INV-4 / Lens 2:** No domain types are imported in this file.
/// - Capabilities are held as [OrgCapabilitiesViewModel] (application layer).
/// - Preset resolution goes through [OrgPresetViewModel] (application layer).
class TenantHealthPanel extends ConsumerStatefulWidget {
  const TenantHealthPanel({super.key});

  @override
  ConsumerState<TenantHealthPanel> createState() => _TenantHealthPanelState();
}

class _TenantHealthPanelState extends ConsumerState<TenantHealthPanel> {
  TenantHealthView? _selectedTenant;

  @override
  Widget build(BuildContext context) {
    // INV-11: Mantém _selectedTenant sincronizado quando o provider é invalidado
    // (ex: após archive/unarchive, o painel filho reflete o novo status sem cache local).
    ref.listen<AsyncValue<List<TenantHealthView>>>(
      tenantHealthSnapshotProvider,
      (_, next) {
        if (next case AsyncData(:final value)) {
          if (_selectedTenant == null || !mounted) return;
          final updated = value
              .where((t) => t.id == _selectedTenant!.id)
              .firstOrNull;
          if (updated != null) setState(() => _selectedTenant = updated);
        }
      },
    );
    return Row(
      children: [
        TenantListPanel(
          selectedOrgId: _selectedTenant?.id,
          onOrgSelected: (tenant) => setState(() => _selectedTenant = tenant),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedTenant != null
              ? TenantDetailPanel(
                  key: ValueKey(_selectedTenant!.id),
                  tenant: _selectedTenant!,
                )
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 64,
                        color: VeraProbColors.textDisabled,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Selecione uma organização na lista ao lado.',
                        style: TextStyle(
                          color: VeraProbColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Overlay modal for editing an organization's plan type and quota limits.
///
/// INV-24: Uses showDialog (overlay modal) for nested edit flows.
///
/// **INV-4 / Lens 2:** Internal state uses [OrgCapabilitiesViewModel]
/// (application layer). Preset resolution goes through [OrgPresetViewModel].
/// Domain conversion happens exclusively inside [UpdateQuotaFormData.toCommand].
class _EditQuotaDialog extends ConsumerStatefulWidget {
  final TenantHealthView snapshot;

  const _EditQuotaDialog({required this.snapshot});

  @override
  ConsumerState<_EditQuotaDialog> createState() => _EditQuotaDialogState();
}

class _EditQuotaDialogState extends ConsumerState<_EditQuotaDialog> {
  late PlanType _selectedPlan;
  late final TextEditingController _maxVehiclesCtrl;
  late final TextEditingController _maxContractsCtrl;
  late final TextEditingController _toolCostCtrl;
  final TextEditingController _reasonCtrl = TextEditingController();
  String? _selectedPreset;

  /// Internal capabilities state held as a presentation-safe ViewModel.
  /// No [OrgCapabilities] (domain) here — it lives entirely in the
  /// application layer.
  late OrgCapabilitiesViewModel _capabilities;

  late int _dwellTimeSeconds;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.snapshot.planType != null
        ? PlanType.fromDb(widget.snapshot.planType!)
        : PlanType.starter;
    _maxVehiclesCtrl = TextEditingController(
      text: widget.snapshot.maxVehicles == 0
          ? ''
          : '${widget.snapshot.maxVehicles}',
    );
    _maxContractsCtrl = TextEditingController(
      text: widget.snapshot.maxActiveContracts == 0
          ? ''
          : '${widget.snapshot.maxActiveContracts}',
    );
    // snapshot.capabilities is already OrgCapabilitiesViewModel — no conversion needed
    _capabilities = widget.snapshot.capabilities;
    _dwellTimeSeconds = widget.snapshot.dwellTimeSeconds;
    _toolCostCtrl = TextEditingController(
      text: widget.snapshot.toolCostCents != null
          ? BrlCurrencyInputFormatter.fromCents(widget.snapshot.toolCostCents!)
          : '',
    );
  }

  @override
  void dispose() {
    _maxVehiclesCtrl.dispose();
    _maxContractsCtrl.dispose();
    _toolCostCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _isEnterprise => _selectedPlan == PlanType.enterprise;

  /// Resolves capabilities from the selected preset via the application-layer
  /// façade [OrgPresetViewModel], without importing any domain type.
  void _onPresetChanged(String? preset) {
    setState(() {
      _selectedPreset = preset;
      _capabilities = preset != null
          ? OrgPresetViewModel.resolveCapabilities(preset)
          : _capabilities;
    });
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final int? maxVehicles = _isEnterprise
        ? null
        : int.tryParse(_maxVehiclesCtrl.text.trim());
    final int? maxContracts = _isEnterprise
        ? null
        : int.tryParse(_maxContractsCtrl.text.trim());

    if (!_isEnterprise && maxVehicles == null) {
      setState(() {
        _errorMessage = 'Informe um número válido para o limite de veículos.';
      });
      return;
    }
    if (!_isEnterprise && maxContracts == null) {
      setState(() {
        _errorMessage =
            'Informe um número válido para o limite de contratos ativos.';
      });
      return;
    }

    final toolCostCents = BrlCurrencyInputFormatter.toCents(_toolCostCtrl.text);
    if (toolCostCents == null) {
      setState(() {
        _errorMessage = 'Informe o custo mensal da ferramenta.';
      });
      return;
    }

    // Stage C: Mandatory reason for governance changes
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() {
        _errorMessage = 'Motivo da alteração é obrigatório.';
      });
      return;
    }
    if (reason.length < 10) {
      setState(() {
        _errorMessage = 'Motivo deve ter pelo menos 10 caracteres.';
      });
      return;
    }

    final superAdminId = ref.read(currentSuperAdminIdProvider);
    if (superAdminId == null) {
      setState(() {
        _errorMessage = 'Sessão inválida. Faça login novamente.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final cmd = UpdateQuotaFormData(
      organizationId: widget.snapshot.id,
      newPlanType: _selectedPlan.dbValue,
      newMaxVehicles: maxVehicles,
      newMaxActiveContracts: maxContracts,
      superAdminUserId: superAdminId,
      reason: _reasonCtrl.text.trim(),
      // _capabilities is OrgCapabilitiesViewModel — toCommand() converts to domain
      capabilities: _capabilities,
      toolCostCents: toolCostCents,
      dwellTimeSeconds: _dwellTimeSeconds,
    ).toCommand();

    try {
      await ref.read(updateOrganizationQuotaHandlerProvider).handle(cmd);

      if (!mounted) return;
      ref.invalidate(tenantHealthSnapshotProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cotas de ${widget.snapshot.name} atualizadas com sucesso.',
          ),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } on DomainException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isSaving = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Não foi possível atualizar as cotas. Tente novamente.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar Cotas — ${widget.snapshot.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<PlanType>(
              initialValue: _selectedPlan,
              decoration: const InputDecoration(labelText: 'Plano'),
              items: PlanType.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (v) => setState(() => _selectedPlan = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxVehiclesCtrl,
              enabled: !_isEnterprise && !_isSaving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Limite de Veículos',
                hintText: _isEnterprise ? 'Ilimitado (enterprise)' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _maxContractsCtrl,
              enabled: !_isEnterprise && !_isSaving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Limite de Contratos Ativos',
                hintText: _isEnterprise ? 'Ilimitado (enterprise)' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              enabled: !_isSaving,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo da Alteração *',
                hintText: 'Mínimo 10 caracteres',
                helperText: 'Obrigatório para mudanças de governança',
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            ExpansionTile(
              title: const Text(
                'Configuração Operacional',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: [
                const SizedBox(height: 8),
                Text(
                  'Tipo de Operação',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                // OrgPresetViewModel.labels replaces OrgVerticalPreset.labels
                SegmentedButton<String>(
                  segments: OrgPresetViewModel.labels.entries
                      .map(
                        (e) => ButtonSegment<String>(
                          value: e.key,
                          label: Text(
                            e.value,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  selected: _selectedPreset != null ? {_selectedPreset!} : {},
                  emptySelectionAllowed: true,
                  onSelectionChanged: _isSaving
                      ? null
                      : (s) => _onPresetChanged(s.isEmpty ? null : s.first),
                ),
                if (_selectedPreset != null) ...[
                  const SizedBox(height: 8),
                  OrgCapabilitiesEditor(
                    capabilities: _capabilities,
                    onToggled: (key, value) => setState(() {
                      _capabilities = switch (key) {
                        'allows_sealing' => _capabilities.copyWith(
                          allowsSealing: value,
                        ),
                        'allows_loading' => _capabilities.copyWith(
                          allowsLoading: value,
                        ),
                        'allows_cargo_check' => _capabilities.copyWith(
                          allowsCargoCheck: value,
                        ),
                        'allows_incident' => _capabilities.copyWith(
                          allowsIncident: value,
                        ),
                        'allows_doc' => _capabilities.copyWith(
                          allowsDoc: value,
                        ),
                        'smart_classify' => _capabilities.copyWith(
                          smartClassify: value,
                        ),
                        _ => _capabilities,
                      };
                    }),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _toolCostCtrl,
                  enabled: !_isSaving,
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
                ),
                const SizedBox(height: 16),
                Text(
                  'Tempo de Parada Padrão: ${_dwellTimeSeconds}s (~${(_dwellTimeSeconds / 60).round()} min)',
                  style: const TextStyle(
                    fontSize: 12,
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
                    value: _dwellTimeSeconds.toDouble(),
                    min: 60,
                    max: 1800,
                    divisions: 29,
                    label: '${_dwellTimeSeconds}s',
                    onChanged: _isSaving
                        ? null
                        : (v) => setState(() => _dwellTimeSeconds = v.round()),
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: VeraProbColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
