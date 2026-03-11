import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../domain/sla_audit/contractual_execution_state.dart';
import '../../../../../domain/sla_audit/execution_status.dart';

class InvestigationMapPanel extends StatelessWidget {
  final ContractualExecutionState execution;

  const InvestigationMapPanel({super.key, required this.execution});

  @override
  Widget build(BuildContext context) {
    // Basic center based on start geofence
    final center = LatLng(execution.startLatitude, execution.startLongitude);
    
    // Convert status to visual color
    Color statusColor = BusFlowColors.info;
    if (execution.status == ExecutionStatus.noShow ||
        execution.status == ExecutionStatus.evidenceGap) {
      statusColor = BusFlowColors.error;
    } else if (execution.status == ExecutionStatus.executed) {
      statusColor = BusFlowColors.success;
    }

    return Card(
      elevation: 0,
      color: BusFlowColors.surfaceElevated,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.map, size: 16, color: BusFlowColors.secondary),
                const SizedBox(width: 8),
                Text(
                  'Camada Geoespacial (Local de Origem)',
                  style: BusFlowTypography.sectionTitle.copyWith(
                    color: BusFlowColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 15.0,
                    interactionOptions: const InteractionOptions(
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
                          point: center,
                          color: statusColor.withValues(alpha: 0.2),
                          borderColor: statusColor,
                          borderStrokeWidth: 2,
                          useRadiusInMeter: true,
                          radius: execution.startRadiusMeters.toDouble(), // Geofence
                        ),
                      ],
                    ),
                    if (execution.status == ExecutionStatus.executed &&
                        execution.bindingTimestampUtc != null) ...[
                      MarkerLayer(
                        markers: [
                          _buildGlowMarker(
                            point: center,
                            color: statusColor,
                            size: 40, 
                          ),
                        ],
                      ),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'O mapa ilustra a cerca virtual de origem (raio de ${execution.startRadiusMeters}m).',
              style: BusFlowTypography.caption,
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildGlowMarker({
    required LatLng point,
    required Color color,
    required double size,
  }) {
    return Marker(
      point: point,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.7),
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}
