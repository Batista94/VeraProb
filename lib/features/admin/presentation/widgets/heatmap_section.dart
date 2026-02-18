import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class HeatmapSection extends StatelessWidget {
  const HeatmapSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mapa de Calor (Lotação)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 400,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(-23.550520, -46.633308),
                    initialZoom: 13.0,
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.none, // Static map
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.busflow.app',
                    ),
                    CircleLayer(
                      circles: [
                        // Mock Heatmap Data (Red = High Density)
                        CircleMarker(
                          point: const LatLng(-23.550520, -46.633308), // Centro
                          color: Colors.red.withValues(alpha: 0.3),
                          borderStrokeWidth: 0,
                          useRadiusInMeter: true,
                          radius: 1500, // 1.5km
                        ),
                        CircleMarker(
                          point: const LatLng(-23.565, -46.650), // Av Paulista
                          color: Colors.orange.withValues(alpha: 0.3),
                          borderStrokeWidth: 0,
                          useRadiusInMeter: true,
                          radius: 1000,
                        ),
                        CircleMarker(
                          point: const LatLng(-23.585, -46.665), // Ibirapuera
                          color: Colors.green.withValues(alpha: 0.3),
                          borderStrokeWidth: 0,
                          useRadiusInMeter: true,
                          radius: 1200,
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
    );
  }
}
