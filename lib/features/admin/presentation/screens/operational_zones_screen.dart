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
/// Uma "Zona Operacional" é uma área geofenceada nomeada (ex: "Garagem Central")
/// que os operadores referenciam ao declarar padrões de turno B2B.
/// Lat/lng são snapshotados no SET no momento da projeção.
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
                label: const Text('Nova Zona'),
                onPressed: () => _showCreateDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Áreas geofenceadas usadas como origem/destino nas viagens programadas.',
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
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: BusFlowColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.place, color: BusFlowColors.primary, size: 20),
          ),
          title: Text(z.name, style: BusFlowTypography.kpiLabel),
          subtitle: Text(
            'Zona Protegida · Raio Operacional: ${z.radiusMeters} m',
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
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController(text: '200');

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
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

      final zone = OperationalZone.create(
        organizationId: orgId,
        name: _nameController.text.trim(),
        latitude: double.parse(_latController.text),
        longitude: double.parse(_lngController.text),
        radiusMeters: int.parse(_radiusController.text),
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
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      decoration: const InputDecoration(labelText: 'Latitude *'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                      ],
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        if (n == null) return 'Inválido';
                        if (n < -90 || n > 90) return '-90 a 90';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      decoration: const InputDecoration(labelText: 'Longitude *'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                      ],
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        if (n == null) return 'Inválido';
                        if (n < -180 || n > 180) return '-180 a 180';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _radiusController,
                decoration: const InputDecoration(
                  labelText: 'Raio (metros) *',
                  hintText: '200',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0 || n > 50000) return '1 a 50000 m';
                  return null;
                },
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
