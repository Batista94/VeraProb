import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';

import '../../../widgets/zone_type_ahead_field.dart';

class DeclarePlanZonesStep extends ConsumerWidget {
  final String contractorName;
  final OperationalZone? selectedOriginZone;
  final String? selectedOriginZoneId;
  final OperationalZone? selectedDestinationZone;
  final String? selectedDestinationZoneId;
  final void Function(OperationalZone? zone) onOriginChanged;
  final void Function(OperationalZone zone) onOriginConfigured;
  final void Function(OperationalZone? zone) onDestinationChanged;
  final void Function(OperationalZone zone) onDestinationConfigured;
  final VoidCallback onSwap;

  const DeclarePlanZonesStep({
    super.key,
    required this.contractorName,
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

    return zonesAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Erro ao carregar zonas operacionais: $e',
          style: const TextStyle(color: VeraProbColors.error),
        ),
      ),
      data: (zones) {
        final contractorZones = zones
            .where(
              (z) =>
                  z.contractorLabel == contractorName &&
                  contractorName.isNotEmpty,
            )
            .toList();
        final otherZones = zones
            .where(
              (z) =>
                  z.contractorLabel != contractorName || contractorName.isEmpty,
            )
            .toList();
        final sortedZones = [...contractorZones, ...otherZones];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecione as zonas operacionais (geofences) que delineiam esta rota B2B.',
              style: TextStyle(color: VeraProbColors.textSecondary),
            ),
            const SizedBox(height: VeraProbSpacing.md),
            ZoneTypeAheadField(
              key: ValueKey('origin_$selectedOriginZoneId'),
              label: 'Zona de Partida',
              prefixIcon: Icons.business,
              zones: sortedZones,
              selectedZone: selectedOriginZone,
              contractorName: contractorName,
              onInvalidateZones: () =>
                  ref.refresh(operationalZonesProvider.future),
              onChanged: onOriginChanged,
              onGeofenceConfigured: onOriginConfigured,
            ),
            Center(
              child: IconButton(
                icon: const Icon(
                  Icons.swap_vert,
                  color: VeraProbColors.primary,
                ),
                tooltip: 'Inverter Origem/Destino',
                onPressed: onSwap,
              ),
            ),
            ZoneTypeAheadField(
              key: ValueKey('destination_$selectedDestinationZoneId'),
              label: 'Zona de Chegada (Destino)',
              prefixIcon: Icons.location_on,
              zones: sortedZones,
              selectedZone: selectedDestinationZone,
              contractorName: contractorName,
              onInvalidateZones: () =>
                  ref.refresh(operationalZonesProvider.future),
              onChanged: onDestinationChanged,
              onGeofenceConfigured: onDestinationConfigured,
            ),
          ],
        );
      },
    );
  }
}
