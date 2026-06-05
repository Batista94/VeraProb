import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/admin/operational_zone_view.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';

import 'package:veraprob/features/admin/presentation/widgets/zone_type_ahead_field.dart';

class DeclarePlanZonesStep extends ConsumerWidget {
  final OperationalZoneView? selectedOriginZone;
  final String? selectedOriginZoneId;
  final OperationalZoneView? selectedDestinationZone;
  final String? selectedDestinationZoneId;
  final void Function(OperationalZoneView? zone) onOriginChanged;
  final void Function(OperationalZoneView zone) onOriginConfigured;
  final void Function(OperationalZoneView? zone) onDestinationChanged;
  final void Function(OperationalZoneView zone) onDestinationConfigured;
  final VoidCallback onSwap;

  const DeclarePlanZonesStep({
    super.key,
    required this.selectedOriginZone,
    required this.selectedOriginZoneId,
    required this.selectedDestinationZone,
    required this.selectedDestinationZoneId,
    required this.onOriginChanged,
    required this.onOriginConfigured,
    required this.onDestinationChanged,
    required this.onDestinationConfigured,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(operationalZonesProvider);

    return switch (zonesAsync) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selecione as zonas de partida e chegada desta rota para ativar o monitoramento.',
            style: TextStyle(color: VeraProbColors.textSecondary),
          ),
          const SizedBox(height: VeraProbSpacing.md),
          ZoneTypeAheadField(
            key: ValueKey('origin_$selectedOriginZoneId'),
            label: 'Zona de Partida',
            prefixIcon: Icons.business,
            zones: value,
            selectedZone: selectedOriginZone,
            onInvalidateZones: () =>
                ref.refresh(operationalZonesProvider.future),
            onChanged: onOriginChanged,
            onGeofenceConfigured: onOriginConfigured,
          ),
          Center(
            child: IconButton(
              icon: const Icon(Icons.swap_vert, color: VeraProbColors.primary),
              tooltip: 'Inverter Origem/Destino',
              onPressed: onSwap,
            ),
          ),
          ZoneTypeAheadField(
            key: ValueKey('destination_$selectedDestinationZoneId'),
            label: 'Zona de Chegada (Destino)',
            prefixIcon: Icons.location_on,
            zones: value,
            selectedZone: selectedDestinationZone,
            onInvalidateZones: () =>
                ref.refresh(operationalZonesProvider.future),
            onChanged: onDestinationChanged,
            onGeofenceConfigured: onDestinationConfigured,
          ),
        ],
      ),
      AsyncLoading() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      AsyncError(:final error) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Erro ao carregar zonas operacionais: $error',
          style: const TextStyle(color: VeraProbColors.error),
        ),
      ),
    };
  }
}
