import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/domain/sla_audit/operational_zone.dart';
import 'package:busflow/state/providers/auth_providers.dart';
import 'package:busflow/state/providers/operational_zone_providers.dart';

/// Tela de gestão de Zonas Operacionais.
///
/// Uma "Zona Operacional" é uma área nomeada (ex: "Garagem Central") que os
/// operadores referenciam ao declarar padrões de turno B2B. O geofence
/// (lat/lng/raio) é opcional — zonas sem geofence são válidas e identificadas
/// apenas por nome/id.
class OperationalZonesScreen extends ConsumerWidget {
  const OperationalZonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(operationalZonesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 28, color: BusFlowColors.primary),
              const SizedBox(width: 12),
              Text('Zonas Operacionais', style: BusFlowTypography.sectionTitle),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nova Zona Operacional'),
                onPressed: () => _showCreateDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Garagens, clientes e pontos de apoio usados como origem/destino nas viagens programadas.',
            style: BusFlowTypography.bodyMedium.copyWith(color: BusFlowColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // ── Zone list ────────────────────────────────────────
          Expanded(
            child: zonesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar zonas: $e',
                  style: BusFlowTypography.bodyMedium.copyWith(color: BusFlowColors.error),
                ),
              ),
              data: (zones) => zones.isEmpty
                  ? _EmptyState(onCreateTap: () => _showCreateDialog(context, ref))
                  : _ZoneList(zones: zones),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateZoneDialog(ref: ref),
    );
  }
}

// ── Zone list ────────────────────────────────────────────────

extension on ZoneType {
  String get label {
    switch (this) {
      case ZoneType.garagem:
        return 'Garagem';
      case ZoneType.cliente:
        return 'Cliente';
      case ZoneType.apoio:
        return 'Apoio';
    }
  }

  IconData get icon {
    switch (this) {
      case ZoneType.garagem:
        return Icons.garage_outlined;
      case ZoneType.cliente:
        return Icons.business_outlined;
      case ZoneType.apoio:
        return Icons.support_agent_outlined;
    }
  }
}

class _ZoneList extends StatelessWidget {
  final List<OperationalZone> zones;

  const _ZoneList({required this.zones});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: zones.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: BusFlowColors.border),
      itemBuilder: (context, i) {
        final z = zones[i];
        final hasGeofence = z.geofence != null;
        final geofenceInfo = hasGeofence
            ? 'Geofence: ${z.geofence!.radiusMeters} m'
            : 'Sem geofence — somente referência manual';
        final addressInfo = z.address ?? 'N/D';

        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: BusFlowColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(z.type.icon, color: BusFlowColors.primary, size: 20),
          ),
          title: Row(
            children: [
              Text(z.name, style: BusFlowTypography.kpiLabel),
              const SizedBox(width: 8),
              _TypeChip(label: z.type.label),
              if (!hasGeofence) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Zona sem geofence. Não pode ser usada em projeções automáticas de viagem.',
                  child: const Icon(
                    Icons.location_off,
                    size: 16,
                    color: BusFlowColors.warning,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            '$addressInfo · $geofenceInfo',
            style: BusFlowTypography.caption.copyWith(color: BusFlowColors.textSecondary),
          ),
          trailing: Text(
            'ID: ${z.id.substring(0, 8)}',
            style: BusFlowTypography.caption.copyWith(
              color: BusFlowColors.textDisabled,
              fontFamily: 'monospace',
            ),
          ),
        );
      },
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;

  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: BusFlowColors.border),
      ),
      child: Text(
        label,
        style: BusFlowTypography.caption.copyWith(color: BusFlowColors.textSecondary),
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;

  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place_outlined, size: 56, color: BusFlowColors.textDisabled),
          const SizedBox(height: 16),
          Text(
            'Nenhuma zona criada ainda',
            style: BusFlowTypography.sectionTitle.copyWith(color: BusFlowColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie zonas operacionais para usar como origem e destino\nnas viagens programadas por padrão de turno.',
            textAlign: TextAlign.center,
            style: BusFlowTypography.bodyMedium.copyWith(color: BusFlowColors.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Criar Primeira Zona'),
            onPressed: onCreateTap,
          ),
        ],
      ),
    );
  }
}

// ── Create zone dialog ───────────────────────────────────────

class _CreateZoneDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;

  const _CreateZoneDialog({required this.ref});

  @override
  ConsumerState<_CreateZoneDialog> createState() => _CreateZoneDialogState();
}

class _CreateZoneDialogState extends ConsumerState<_CreateZoneDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController(text: '200');

  ZoneType _selectedType = ZoneType.garagem;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_clearError);
    _addressController.addListener(_clearError);
    _latController.addListener(_clearError);
    _lngController.addListener(_clearError);
    _radiusController.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  bool get _hasGeofenceInput =>
      _latController.text.trim().isNotEmpty &&
      _lngController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      if (orgId == null) throw const DomainException('Sessão expirada. Faça login novamente.');

      GeofenceConfiguration? geofence;
      if (_hasGeofenceInput) {
        final lat = double.tryParse(_latController.text.trim().replaceAll(',', '.'));
        final lng = double.tryParse(_lngController.text.trim().replaceAll(',', '.'));
        final radius = int.tryParse(_radiusController.text.trim()) ?? 200;
        if (lat == null || lng == null) {
          throw const DomainException('Latitude e longitude devem ser números decimais válidos.');
        }
        geofence = GeofenceConfiguration(
          latitude: lat,
          longitude: lng,
          radiusMeters: radius,
        );
      }

      final zone = OperationalZone.create(
        organizationId: orgId,
        name: _nameController.text.trim(),
        type: _selectedType,
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        geofence: geofence,
      );

      await saveZone(zone, ref);

      if (mounted) Navigator.of(context).pop();
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
    return AlertDialog(
      title: const Text('Nova Zona Operacional'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Tipo ──────────────────────────────────────
                DropdownButtonFormField<ZoneType>(
                  value: _selectedType,
                  decoration: const InputDecoration(labelText: 'Tipo *'),
                  items: ZoneType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Row(
                            children: [
                              Icon(t.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(t.label),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
                const SizedBox(height: 16),

                // ── Nome ──────────────────────────────────────
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome *',
                    hintText: 'Ex: Garagem Central, Portaria Sul',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                  autofocus: true,
                ),
                const SizedBox(height: 16),

                // ── Endereço ──────────────────────────────────
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Endereço',
                    hintText: 'Ex: Av. Paulista, 1000 — São Paulo/SP',
                  ),
                ),
                const SizedBox(height: 16),

                // ── Geofence (avançado) ───────────────────────
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      'Avançado: Configurar Geofence',
                      style: BusFlowTypography.caption.copyWith(
                        color: BusFlowColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _hasGeofenceInput
                          ? 'Geofence configurado · Raio: ${_radiusController.text} m'
                          : 'Opcional — obrigatório para auditoria automática de chegada/partida',
                      style: BusFlowTypography.caption.copyWith(
                        color: _hasGeofenceInput
                            ? BusFlowColors.primary
                            : BusFlowColors.textDisabled,
                      ),
                    ),
                    children: [
                      // Warning label
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: BusFlowColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: BusFlowColors.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 16, color: BusFlowColors.warning),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Geofence obrigatório para auditoria automática de chegada/partida '
                                'pelo motor de avaliação. Zonas sem geofence só podem ser usadas '
                                'como referência manual.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: BusFlowColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Lat / Lng row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latController,
                              decoration: const InputDecoration(
                                labelText: 'Latitude (graus decimais)',
                                hintText: 'Ex: -23.5505',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  signed: true, decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^-?\d*[.,]?\d*')),
                              ],
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final parsed = double.tryParse(
                                    v.trim().replaceAll(',', '.'));
                                if (parsed == null ||
                                    parsed < -90 ||
                                    parsed > 90) {
                                  return '-90 a 90';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _lngController,
                              decoration: const InputDecoration(
                                labelText: 'Longitude (graus decimais)',
                                hintText: 'Ex: -46.6333',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  signed: true, decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^-?\d*[.,]?\d*')),
                              ],
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final parsed = double.tryParse(
                                    v.trim().replaceAll(',', '.'));
                                if (parsed == null ||
                                    parsed < -180 ||
                                    parsed > 180) {
                                  return '-180 a 180';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Radius
                      TextFormField(
                        controller: _radiusController,
                        decoration: const InputDecoration(
                          labelText: 'Raio (metros)',
                          hintText: '200',
                          suffixText: 'm',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          final n = int.tryParse(v);
                          if (n == null || n <= 0 || n > 50000) return '1 a 50000 m';
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: BusFlowTypography.caption.copyWith(color: BusFlowColors.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Criar Zona'),
        ),
      ],
    );
  }
}
