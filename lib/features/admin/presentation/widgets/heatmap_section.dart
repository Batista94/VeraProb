import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';

class HeatmapSection extends StatelessWidget {
  const HeatmapSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Projeção de Risco Operacional',
              style: BusFlowTypography.sectionTitle.copyWith(
                color: BusFlowColors.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 400,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(-23.550520, -46.633308),
                    initialZoom: 12.0,
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.busflow.app',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: const LatLng(-23.550520, -46.633308),
                          color: BusFlowColors.critical.withValues(alpha: 0.3),
                          borderStrokeWidth: 0,
                          useRadiusInMeter: true,
                          radius: 2000,
                        ),
                        CircleMarker(
                          point: const LatLng(-23.565, -46.650),
                          color: BusFlowColors.delayed.withValues(alpha: 0.3),
                          borderStrokeWidth: 0,
                          useRadiusInMeter: true,
                          radius: 1200,
                        ),
                        CircleMarker(
                          point: const LatLng(-23.585, -46.665),
                          color: BusFlowColors.onTime.withValues(alpha: 0.3),
                          borderStrokeWidth: 0,
                          useRadiusInMeter: true,
                          radius: 1500,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Fonte: Event Audit Ledger • Projeção geoespacial baseada em SLR (Service Level Risk)',
              style: BusFlowTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}
