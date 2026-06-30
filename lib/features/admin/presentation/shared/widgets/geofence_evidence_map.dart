import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:veraprob/core/config/constants.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// A read-only (INV-23) mini-map displaying geofence evidence for audit cards.
///
/// Shows:
/// - Dark-styled map tiles (reuses MapTiler / OSM fallback)
/// - Optional geofence circle (stop radius)
/// - Optional track polyline (recent breadcrumb trail)
/// - Infraction marker (vehicle position at the moment of the event)
///
/// Pure [StatelessWidget] — no controller, no Riverpod, no mutation.
/// Auto-fits bounds from the geofence + infraction point.
class GeofenceEvidenceMap extends StatelessWidget {
  /// The infraction/event position (required).
  final LatLng infractionPoint;

  /// Optional geofence center (e.g., bus stop).
  final LatLng? geofenceCenter;

  /// Geofence radius in metres. Only rendered if [geofenceCenter] is set.
  final double geofenceRadiusMeters;

  /// Optional recent track polyline (breadcrumb trail).
  final List<LatLng> trackPoints;

  /// Color for the infraction marker.
  final Color markerColor;

  /// Widget height. Width fills available space.
  final double height;

  const GeofenceEvidenceMap({
    super.key,
    required this.infractionPoint,
    this.geofenceCenter,
    this.geofenceRadiusMeters = 50.0,
    this.trackPoints = const [],
    this.markerColor = VeraProbColors.critical,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    final bounds = _computeBounds();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: bounds.center,
            initialZoom: _zoomForBounds(bounds),
            minZoom: 10,
            maxZoom: 18,
            backgroundColor: VeraProbColors.background,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrl(),
              userAgentPackageName: 'com.veraprob.admin',
              tileBuilder: _darkTileBuilder,
            ),

            // Geofence circle
            if (geofenceCenter != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: geofenceCenter!,
                    radius: geofenceRadiusMeters,
                    useRadiusInMeter: true,
                    color: VeraProbColors.scheduled.withValues(alpha: 0.12),
                    borderColor: VeraProbColors.scheduled.withValues(
                      alpha: 0.6,
                    ),
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),

            // Track polyline
            if (trackPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trackPoints,
                    color: VeraProbColors.primary.withValues(alpha: 0.6),
                    strokeWidth: 2.0,
                  ),
                ],
              ),

            // Infraction marker
            MarkerLayer(
              markers: [
                Marker(
                  point: infractionPoint,
                  width: 16,
                  height: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: markerColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: VeraProbColors.textPrimary,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: markerColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Computes a bounding box that fits all visible features.
  LatLngBounds _computeBounds() {
    final points = <LatLng>[infractionPoint];
    if (geofenceCenter != null) {
      points.add(geofenceCenter!);
      // Add geofence edge points for proper zoom
      final offsetDeg = geofenceRadiusMeters / 111320.0;
      points.add(
        LatLng(
          geofenceCenter!.latitude + offsetDeg,
          geofenceCenter!.longitude + offsetDeg,
        ),
      );
      points.add(
        LatLng(
          geofenceCenter!.latitude - offsetDeg,
          geofenceCenter!.longitude - offsetDeg,
        ),
      );
    }
    points.addAll(trackPoints);

    if (points.length == 1) {
      // Single point — create a small bounding box around it
      const pad = 0.002;
      return LatLngBounds(
        LatLng(points.first.latitude - pad, points.first.longitude - pad),
        LatLng(points.first.latitude + pad, points.first.longitude + pad),
      );
    }

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    // Add 20% padding
    final latPad = (maxLat - minLat) * 0.2;
    final lngPad = (maxLng - minLng) * 0.2;
    return LatLngBounds(
      LatLng(minLat - latPad, minLng - lngPad),
      LatLng(maxLat + latPad, maxLng + lngPad),
    );
  }

  /// Estimate zoom level from bounding box size.
  double _zoomForBounds(LatLngBounds bounds) {
    final latDiff = bounds.north - bounds.south;
    final lngDiff = bounds.east - bounds.west;
    final maxDiff = math.max(latDiff, lngDiff);

    if (maxDiff <= 0) return 16.0;
    // Approximate: each zoom level halves the visible span
    final zoom = 16.0 - (math.log(maxDiff * 1000) / math.ln2);
    return zoom.clamp(10.0, 18.0);
  }

  static String _tileUrl() {
    if (AppConstants.mapTilerKey != 'get_your_own_key') {
      return AppConstants.mapTileUrl.replaceAll(
        '{key}',
        AppConstants.mapTilerKey,
      );
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  static Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    if (kIsWeb) return tileWidget;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.8,
        0.0,
        0.0,
        0.0,
        40.0,
        0.0,
        -0.8,
        0.0,
        0.0,
        40.0,
        0.0,
        0.0,
        -0.8,
        0.0,
        50.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ]),
      child: tileWidget,
    );
  }
}
