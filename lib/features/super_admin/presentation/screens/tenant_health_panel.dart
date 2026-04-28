import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/core/utils/brl_currency_input_formatter.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/update_quota_form_data.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/super_admin/org_vertical_preset.dart';
import 'package:veraprob/features/super_admin/presentation/screens/widgets/organization_wizard_steps.dart';
import 'package:veraprob/presentation/shared/widgets/info_tooltip.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';

/// Cross-tenant health dashboard for SuperAdmin.
///
/// Displays one row per organization with key health indicators.
/// Critical alert count shown with a red badge.
class TenantHealthPanel extends ConsumerWidget {
  const TenantHealthPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(tenantHealthSnapshotProvider);

    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: VeraProbColors.error,
            ),
            const SizedBox(height: 12),
            Text('Erro ao carregar tenants: $err'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(tenantHealthSnapshotProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
      data: (tenants) => _TenantTable(tenants: tenants, ref: ref),
    );
  }
}

class _TenantTable extends StatelessWidget {
  final List<TenantHealthView> tenants;
  final WidgetRef ref;

  const _TenantTable({required this.tenants, required this.ref});

  @override
  Widget build(BuildContext context) {
    if (tenants.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.business_outlined,
              size: 64,
              color: VeraProbColors.textDisabled,
            ),
            SizedBox(height: 16),
            Text(
              'Nenhum tenant cadastrado.',
              style: TextStyle(
                fontSize: 16,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Tenants (${tenants.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => ref.invalidate(tenantHealthSnapshotProvider),
                icon: const Icon(Icons.refresh),
                tooltip: 'Atualizar',
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  VeraProbColors.superAdminSurface.withValues(alpha: 0.3),
                ),
                columns: const [
                  DataColumn(label: Text('Organização')),
                  DataColumn(label: Text('Plano')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Contratos Ativos'), numeric: true),
                  DataColumn(label: Text('Veículos'), numeric: true),
                  DataColumn(label: Text('Último Telemetria')),
                  DataColumn(label: Text('Alertas Críticos')),
                  DataColumn(label: Text('Ações')),
                ],
                rows: tenants.map((t) => _buildRow(context, t)).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  DataRow _buildRow(BuildContext context, TenantHealthView t) {
    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (t.legalName != null)
                Text(
                  t.legalName!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
            ],
          ),
        ),
        DataCell(Text(t.planType?.toUpperCase() ?? '—')),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: t.isActive
                  ? VeraProbColors.success.withValues(alpha: 0.15)
                  : VeraProbColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              t.isActive ? 'Ativo' : 'Inativo',
              style: TextStyle(
                color: t.isActive
                    ? VeraProbColors.success
                    : VeraProbColors.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            t.maxActiveContracts == 0
                ? '${t.activeContractCount}/∞'
                : '${t.activeContractCount}/${t.maxActiveContracts}',
            style: TextStyle(
              color: _quotaColor(t.activeContractCount, t.maxActiveContracts),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DataCell(Text(t.maxVehicles == 0 ? '∞' : '${t.maxVehicles}')),
        DataCell(
          Text(
            t.lastTelemetryAt != null
                ? _formatDateTime(t.lastTelemetryAt!)
                : '—',
            style: TextStyle(
              color: t.lastTelemetryAt == null
                  ? VeraProbColors.textDisabled
                  : null,
            ),
          ),
        ),
        DataCell(
          t.hasCriticalAlerts
              ? Badge(
                  label: Text('${t.openCriticalAlertCount}'),
                  backgroundColor: VeraProbColors.error,
                  child: const Icon(
                    Icons.warning_amber,
                    color: VeraProbColors.error,
                    size: 20,
                  ),
                )
              : const Icon(
                  Icons.check_circle_outline,
                  color: VeraProbColors.success,
                  size: 20,
                ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Editar cotas',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _EditQuotaDialog(snapshot: t),
            ),
          ),
        ),
      ],
    );
  }

  Color _quotaColor(int current, int max) {
    if (max == 0) return VeraProbColors.success;
    final ratioBps = (current * 10000) ~/ max;
    if (ratioBps >= 10000) return VeraProbColors.error;
    if (ratioBps >= 8000) return Colors.orange;
    return VeraProbColors.success;
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Overlay modal for editing an organization's plan type and quota limits.
///
/// INV-24: Uses showDialog (overlay modal) for nested edit flows.
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
  late OrgCapabilities _capabilities;
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

  void _onPresetChanged(String? preset) {
    setState(() {
      _selectedPreset = preset;
      _capabilities = preset != null
          ? (OrgVerticalPreset.defaults[preset] ?? _capabilities)
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
      reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
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
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
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
                SegmentedButton<String>(
                  segments: OrgVerticalPreset.labels.entries
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
                  OrgCapabilitiesChips(capabilities: _capabilities),
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
