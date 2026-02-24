import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/domain/entities/vehicle_position.dart';
import 'package:latlong2/latlong.dart';

import '../../../shared/providers.dart';

class BusDetailSheet extends StatelessWidget {
  final VehiclePosition vehicle;
  final Function(String) onReport;

  const BusDetailSheet({
    super.key,
    required this.vehicle,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          vehicle.tripId,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Favorites Star
                        Consumer(
                          builder: (context, ref, child) {
                            final favorites = ref.watch(favoritesProvider);
                            final isFavorite = favorites.contains(
                              vehicle.tripId,
                            );

                            return IconButton(
                              icon: Icon(
                                isFavorite ? Icons.star : Icons.star_border,
                                color: isFavorite ? Colors.amber : Colors.grey,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                ref
                                    .read(favoritesProvider.notifier)
                                    .toggleFavorite(vehicle.tripId);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    Text(
                      vehicle.routeName ?? 'Destino desconhecido',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: vehicle.source == 'api_public'
                      ? Colors.blue[100]
                      : Colors.green[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  vehicle.source == 'api_public' ? 'Oficial' : 'Colaborativo',
                  style: TextStyle(
                    color: vehicle.source == 'api_public'
                        ? Colors.blue[800]
                        : Colors.green[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ETA and Speed Row
          Row(
            children: [
              _buildInfoChip(
                Icons.speed,
                '${((vehicle.speed ?? 0) * 3.6).toStringAsFixed(0)} km/h',
              ),
              const SizedBox(width: 12),
              Consumer(
                builder: (context, ref, _) {
                  final userLocAsync = ref.watch(userLocationStreamProvider);

                  return userLocAsync.when(
                    data: (userPos) {
                      // Calculate ETA
                      // Default speed 15km/h (~4.17 m/s) if bus is stopped/slow
                      final speed =
                          (vehicle.speed != null && vehicle.speed! > 1.0)
                          ? vehicle.speed!
                          : 4.17;

                      final distance = const Distance().as(
                        LengthUnit.Meter,
                        LatLng(userPos.latitude, userPos.longitude),
                        LatLng(vehicle.latitude, vehicle.longitude),
                      );

                      final timeSeconds = distance / speed;
                      final timeMinutes = (timeSeconds / 60).round();

                      return _buildInfoChip(
                        Icons.timer,
                        '~ $timeMinutes min (${(distance / 1000).toStringAsFixed(1)} km)',
                      );
                    },
                    loading: () => _buildInfoChip(Icons.timer, 'Calculando...'),
                    error: (_, _) => _buildInfoChip(Icons.timer, '--'),
                  );
                },
              ),
            ],
          ),
          const Divider(height: 32),
          const Text(
            'Reportar Problema',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildReportButton(context, 'Lotação', Icons.groups),
              _buildReportButton(context, 'Atraso', Icons.timer_off),
              _buildReportButton(context, 'Ar Cond.', Icons.ac_unit),
              _buildReportButton(context, 'Outro', Icons.more_horiz),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  Widget _buildReportButton(BuildContext context, String label, IconData icon) {
    return InkWell(
      onTap: () => onReport(label),
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: Colors.red[50], // Very light red
            radius: 24,
            child: Icon(icon, color: Colors.red[700], size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
