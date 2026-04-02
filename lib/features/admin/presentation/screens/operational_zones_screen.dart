import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/presentation/shared/widgets/info_tooltip.dart';
import 'package:veraprob/presentation/shared/widgets/veraprob_header.dart';
import 'package:veraprob/presentation/shared/widgets/veraprob_chip.dart';

import 'widgets/_zone_form_dialog.dart';
import 'widgets/zone_ui_utils.dart';

// ── Screen ───────────────────────────────────────────────────

/// Tela de gestão de Zonas Operacionais (CRUD completo).
class OperationalZonesScreen extends ConsumerWidget {
  const OperationalZonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(operationalZonesProvider);

    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeraProbHeader(
            icon: Icons.place_outlined,
            title: 'Zonas Operacionais',
            subtitle: 'Garagens, clientes e pontos de apoio.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nova Zona Operacional'),
                onPressed: () async {
                  final saved = await showZoneFormDialog(context);
                  if (saved != null) ref.invalidate(operationalZonesProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: VeraProbSpacing.md),
          Text(
            'Garagens, clientes e pontos de apoio usados como origem/destino '
            'nas viagens programadas. Geofence (coordenadas + raio) é obrigatório '
            'para auditoria automática pelo motor de avaliação.',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: zonesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar zonas: $e',
                  style: VeraProbTypography.bodyMedium.copyWith(
                    color: VeraProbColors.error,
                  ),
                ),
              ),
              data: (zones) => zones.isEmpty
                  ? _EmptyState(
                      onCreateTap: () async {
                        final saved = await showZoneFormDialog(context);
                        if (saved != null) {
                          ref.invalidate(operationalZonesProvider);
                        }
                      },
                    )
                  : _ZoneList(zones: zones),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Zone list ────────────────────────────────────────────────

class _ZoneList extends ConsumerWidget {
  final List<OperationalZone> zones;
  const _ZoneList({required this.zones});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      itemCount: zones.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: VeraProbColors.border),
      itemBuilder: (context, i) {
        final z = zones[i];
        final hasGeofence = z.geofence != null;
        final geoLabel = hasGeofence
            ? '${z.geofence!.radiusMeters} m  ·  '
                  '${z.geofence!.latitude.toStringAsFixed(5)}, '
                  '${z.geofence!.longitude.toStringAsFixed(5)}'
            : 'Sem geofence — configure para auditoria automática';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: VeraProbColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(z.type.icon, color: VeraProbColors.primary, size: 20),
          ),
          title: Row(
            children: [
              Text(z.name, style: VeraProbTypography.kpiLabel),
              const SizedBox(width: 8),
              _TypeChip(label: z.type.label),
              if (!hasGeofence) ...[
                const SizedBox(width: 8),
                const InfoTooltip(
                  message:
                      'Sem geofence — o motor de avaliação não pode auditar '
                      'chegada/partida automaticamente.',
                  variant: InfoTooltipVariant.warning,
                  icon: Icons.location_off,
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                z.address ?? 'Endereço não informado',
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.textSecondary,
                ),
              ),
              Row(
                children: [
                  Icon(
                    hasGeofence ? Icons.my_location : Icons.location_off,
                    size: 12,
                    color: hasGeofence
                        ? VeraProbColors.success
                        : VeraProbColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    geoLabel,
                    style: VeraProbTypography.caption.copyWith(
                      color: hasGeofence
                          ? VeraProbColors.success
                          : VeraProbColors.warning,
                      fontFamily: hasGeofence ? 'monospace' : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                z.id.substring(0, 8),
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.textDisabled,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Editar zona',
                color: VeraProbColors.textSecondary,
                onPressed: () async {
                  final saved = await showZoneFormDialog(
                    context,
                    existingZone: z,
                  );
                  if (saved != null) ref.invalidate(operationalZonesProvider);
                },
              ),
            ],
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
    return VeraProbChip(
      label: label,
      color: VeraProbColors.primary,
      outline: true,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.place_outlined,
            size: 56,
            color: VeraProbColors.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma zona criada ainda',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie zonas operacionais para usar como origem e destino\n'
            'nas viagens programadas por padrão de turno.',
            textAlign: TextAlign.center,
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
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

// ── Place suggestion (Nominatim result) ──────────────────────
