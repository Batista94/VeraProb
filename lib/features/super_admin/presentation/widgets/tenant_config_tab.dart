import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/update_quota_form_data.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/reason_confirmation_dialog.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

class TenantConfigTab extends ConsumerStatefulWidget {
  final TenantHealthView tenant;
  const TenantConfigTab({super.key, required this.tenant});

  @override
  ConsumerState<TenantConfigTab> createState() => _TenantConfigTabState();
}

class _TenantConfigTabState extends ConsumerState<TenantConfigTab> {
  late OrgCapabilitiesViewModel _capabilities;
  final _formKey = GlobalKey<FormState>();

  String? _planType;
  String? _orgType;
  final _tradeNameCtrl = TextEditingController();
  final _legalNameCtrl = TextEditingController();
  final _maxVehiclesCtrl = TextEditingController();
  final _maxContractsCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _dwellTimeCtrl = TextEditingController();
  final _billingDayCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _externalIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initValues(widget.tenant);
  }

  void _initValues(TenantHealthView t) {
    _capabilities = t.capabilities;
    _planType = t.planType;
    _orgType = t.organizationType;
    _tradeNameCtrl.text = t.name;
    _legalNameCtrl.text = t.legalName ?? '';
    _maxVehiclesCtrl.text = t.maxVehicles == 0 ? '' : t.maxVehicles.toString();
    _maxContractsCtrl.text = t.maxActiveContracts == 0
        ? ''
        : t.maxActiveContracts.toString();
    _costCtrl.text = t.toolCostCents != null
        ? (t.toolCostCents! / 100).toStringAsFixed(2)
        : '';
    _dwellTimeCtrl.text = t.dwellTimeSeconds.toString();
    _billingDayCtrl.text = t.billingDay?.toString() ?? '';
    _contactEmailCtrl.text = t.contactEmail ?? '';
    _externalIdCtrl.text = t.externalId ?? '';
  }

  @override
  void didUpdateWidget(covariant TenantConfigTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenant.id != widget.tenant.id ||
        oldWidget.tenant != widget.tenant) {
      _initValues(widget.tenant);
    }
  }

  @override
  void dispose() {
    _tradeNameCtrl.dispose();
    _legalNameCtrl.dispose();
    _maxVehiclesCtrl.dispose();
    _maxContractsCtrl.dispose();
    _costCtrl.dispose();
    _dwellTimeCtrl.dispose();
    _billingDayCtrl.dispose();
    _contactEmailCtrl.dispose();
    _externalIdCtrl.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.'));
    if (_costCtrl.text.isEmpty || cost == null || cost.isNaN || cost < 0) {
      return false;
    }
    if (_billingDayCtrl.text.isNotEmpty) {
      final n = int.tryParse(_billingDayCtrl.text);
      if (n == null || n < 1 || n > 28) return false;
    }
    if (_maxVehiclesCtrl.text.isNotEmpty) {
      final n = int.tryParse(_maxVehiclesCtrl.text);
      if (n == null || n < 1) return false;
    }
    if (_maxContractsCtrl.text.isNotEmpty) {
      final n = int.tryParse(_maxContractsCtrl.text);
      if (n == null || n < 1) return false;
    }
    if (_dwellTimeCtrl.text.isNotEmpty) {
      final n = int.tryParse(_dwellTimeCtrl.text);
      if (n == null || n < 300) return false;
    }
    return true;
  }

  bool get _isDirty {
    final t = widget.tenant;
    final costStr = t.toolCostCents != null
        ? (t.toolCostCents! / 100).toStringAsFixed(2)
        : '';
    final mvStr = t.maxVehicles == 0 ? '' : t.maxVehicles.toString();
    final mcStr = t.maxActiveContracts == 0
        ? ''
        : t.maxActiveContracts.toString();

    return _capabilities != t.capabilities ||
        _planType != t.planType ||
        _orgType != t.organizationType ||
        _tradeNameCtrl.text != t.name ||
        _legalNameCtrl.text != (t.legalName ?? '') ||
        _maxVehiclesCtrl.text != mvStr ||
        _maxContractsCtrl.text != mcStr ||
        _costCtrl.text != costStr ||
        _dwellTimeCtrl.text != t.dwellTimeSeconds.toString() ||
        _billingDayCtrl.text != (t.billingDay?.toString() ?? '') ||
        _contactEmailCtrl.text != (t.contactEmail ?? '') ||
        _externalIdCtrl.text != (t.externalId ?? '');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonConfirmationDialog(),
    );
    if (reason == null || !mounted) return;

    try {
      final t = widget.tenant;
      final costVal =
          double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0.0;

      final cmd = UpdateQuotaFormData(
        organizationId: t.id,
        newPlanType: _planType ?? 'starter',
        newMaxVehicles: int.tryParse(_maxVehiclesCtrl.text),
        newMaxActiveContracts: int.tryParse(_maxContractsCtrl.text),
        superAdminUserId:
            ref.read(authStateProvider).valueOrNull?.session?.user.id ?? '',
        reason: reason,
        capabilities: _capabilities,
        toolCostCents: (costVal * 100).round(),
        dwellTimeSeconds: int.tryParse(_dwellTimeCtrl.text) ?? 300,
        billingDay: int.tryParse(_billingDayCtrl.text),
        contactEmail: _contactEmailCtrl.text.isEmpty
            ? null
            : _contactEmailCtrl.text,
        externalId: _externalIdCtrl.text.isEmpty ? null : _externalIdCtrl.text,
        organizationType: _orgType,
        tradeName: _tradeNameCtrl.text.isEmpty ? null : _tradeNameCtrl.text,
        legalName: _legalNameCtrl.text.isEmpty ? null : _legalNameCtrl.text,
        expectedUpdatedAt: t.updatedAt,
      ).toCommand();

      await ref.read(updateOrganizationQuotaHandlerProvider).handle(cmd);
      ref.invalidate(tenantHealthSnapshotProvider);
      await ref.read(tenantHealthSnapshotProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações atualizadas com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } on DomainException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Identificação'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tradeNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome Fantasia',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _legalNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Razão Social',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('Plano & Limites'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _planType,
              decoration: const InputDecoration(
                labelText: 'Plano',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Não Definido')),
                DropdownMenuItem(value: 'starter', child: Text('Starter')),
                DropdownMenuItem(
                  value: 'professional',
                  child: Text('Professional'),
                ),
                DropdownMenuItem(
                  value: 'enterprise',
                  child: Text('Enterprise'),
                ),
              ],
              onChanged: (v) => setState(() => _planType = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _orgType,
              decoration: const InputDecoration(
                labelText: 'Tipo de Organização',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Não Definido')),
                DropdownMenuItem(value: 'CARGO', child: Text('Cargas (Cargo)')),
                DropdownMenuItem(
                  value: 'PASSENGER',
                  child: Text('Passageiros'),
                ),
                DropdownMenuItem(
                  value: 'URBAN_LOGISTICS',
                  child: Text('Logística Urbana'),
                ),
              ],
              onChanged: (v) => setState(() => _orgType = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _maxVehiclesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Max Veículos (Vazio=Ilimitado)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      final n = int.tryParse(v);
                      if (n == null || n < 1) return 'Mínimo: 1';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _maxContractsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Max Contratos (Vazio=Ilimitado)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      final n = int.tryParse(v);
                      if (n == null || n < 1) return 'Mínimo: 1';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _costCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Custo Ferramenta (R\$)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obrigatório';
                      final n = double.tryParse(v.replaceAll(',', '.'));
                      if (n == null || n.isNaN || n < 0) {
                        return 'Valor inválido (≥ 0)';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _dwellTimeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dwell Time (Segundos)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obrigatório';
                      final n = int.tryParse(v);
                      if (n == null || n < 300) return 'Mínimo: 300s (5min)';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionTitle('Faturamento & Integracao'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _billingDayCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dia de Faturamento (1-28)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null; // optional
                      final n = int.tryParse(v);
                      if (n == null || n < 1 || n > 28) {
                        return 'Dia inválido (1-28)';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _contactEmailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'E-mail de Contato',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _externalIdCtrl,
              decoration: const InputDecoration(
                labelText: 'ID Externo (CRM/ERP)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('Capabilities'),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Lacre'),
              value: _capabilities.allowsSealing,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(allowsSealing: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Carregamento'),
              value: _capabilities.allowsLoading,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(allowsLoading: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Cargo Check'),
              value: _capabilities.allowsCargoCheck,
              onChanged: (v) => setState(
                () =>
                    _capabilities = _capabilities.copyWith(allowsCargoCheck: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Incidente'),
              value: _capabilities.allowsIncident,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(allowsIncident: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Doc'),
              value: _capabilities.allowsDoc,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(allowsDoc: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Smart Classify'),
              value: _capabilities.smartClassify,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(smartClassify: v),
              ),
              dense: true,
            ),
            if (_isDirty && !widget.tenant.isArchived) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isFormValid ? _save : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Salvar Alteracoes'),
                style: FilledButton.styleFrom(
                  backgroundColor: VeraProbColors.superAdminSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: VeraProbColors.textPrimary,
      ),
    );
  }
}
