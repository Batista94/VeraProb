import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
        final geofenceInfo = z.geofence != null
            ? 'Geofence: ${z.geofence!.radiusMeters} m'
            : 'Sem geofence configurado';
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
  final _radiusController = TextEditingController(text: '200');

  ZoneType _selectedType = ZoneType.garagem;
  LatLng? _selectedLocation;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_clearError);
    _addressController.addListener(_clearError);
    _radiusController.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

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
      if (_selectedLocation != null) {
        geofence = GeofenceConfiguration(
          latitude: _selectedLocation!.latitude,
          longitude: _selectedLocation!.longitude,
          radiusMeters: int.parse(_radiusController.text),
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
    final radius = double.tryParse(_radiusController.text) ?? 200.0;

    return AlertDialog(
      title: const Text('Nova Zona Operacional'),
      content: SizedBox(
        width: 600,
        height: 620,
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
                      'Avançado: Ajuste de Geofence',
                      style: BusFlowTypography.caption.copyWith(
                        color: BusFlowColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _selectedLocation == null
                          ? 'Opcional — clique no mapa para definir a área'
                          : 'Geofence configurado · Raio: ${_radiusController.text} m',
                      style: BusFlowTypography.caption.copyWith(
                        color: _selectedLocation != null
                            ? BusFlowColors.primary
                            : BusFlowColors.textDisabled,
                      ),
                    ),
                    children: [
                      TextFormField(
                        controller: _radiusController,
                        decoration: const InputDecoration(
                          labelText: 'Raio (metros)',
                          hintText: '200',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.isEmpty) return null; // optional
                          final n = int.tryParse(v);
                          if (n == null || n <= 0 || n > 50000) return '1 a 50000 m';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 300,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: const LatLng(-23.5505, -46.6333),
                              initialZoom: 13,
                              onTap: (_, point) {
                                setState(() => _selectedLocation = point);
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                                subdomains: const ['a', 'b', 'c', 'd'],
                                userAgentPackageName: 'com.busflow.app',
                              ),
                              if (_selectedLocation != null)
                                CircleLayer(
                                  circles: [
                                    CircleMarker(
                                      point: _selectedLocation!,
                                      color: BusFlowColors.primary.withValues(alpha: 0.3),
                                      borderColor: BusFlowColors.primary,
                                      borderStrokeWidth: 2,
                                      useRadiusInMeter: true,
                                      radius: radius,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
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
