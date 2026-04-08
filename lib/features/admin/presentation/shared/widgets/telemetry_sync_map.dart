import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:veraprob/core/config/constants.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/sanction_focus_provider.dart';

/// Interpolates between two [LatLng] values for smooth camera flight.
class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    return LatLng(
      begin!.latitude + (end!.latitude - begin!.latitude) * t,
      begin!.longitude + (end!.longitude - begin!.longitude) * t,
    );
  }
}

/// Reactive forensic evidence map for the Auditor Queue (WS-5).
///
/// Listens to [selectedSanctionFocusProvider] and animates the camera
/// to the infraction point using a smooth Tween-based flight.
///
/// Design invariants:
/// - **INV-23:** Strictly read-only — no state mutation from map interaction.
/// - **Unidirectional:** List writes → Provider → Map reads.
/// - **Industrial Deep:** Dark tiles, low-luminance palette.
class TelemetrySyncMap extends ConsumerStatefulWidget {
  const TelemetrySyncMap({super.key});

  @override
  ConsumerState<TelemetrySyncMap> createState() => _TelemetrySyncMapState();
}

class _TelemetrySyncMapState extends ConsumerState<TelemetrySyncMap>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final AnimationController _animController;

  /// Current focus state to render markers/circles.
  SanctionMapFocus? _currentFocus;

  /// Pulsing animation for the infraction marker.
  late final Animation<double> _pulseAnimation;

  static const _defaultCenter = LatLng(
    AppConstants.defaultLatitude,
    AppConstants.defaultLongitude,
  );
  static const _defaultZoom = 12.0;
  static const _focusZoom = 16.0;
  static const _flightDuration = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _flightDuration,
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Animate camera flight from current position to [target] at [targetZoom].
  void _flyTo(LatLng target, double targetZoom) {
    final startCenter = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;

    final latLngTween = LatLngTween(begin: startCenter, end: target);
    final zoomTween = Tween<double>(begin: startZoom, end: targetZoom);

    _animController.reset();

    late final Animation<double> curved;
    curved = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOutCubic,
    );

    void listener() {
      final center = latLngTween.evaluate(curved);
      final zoom = zoomTween.evaluate(curved);
      _mapController.move(center, zoom);
    }

    _animController.addListener(listener);
    _animController.forward().whenComplete(() {
      _animController.removeListener(listener);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen to focus changes and animate the camera.
    ref.listen<SanctionMapFocus?>(selectedSanctionFocusProvider, (prev, next) {
      setState(() => _currentFocus = next);

      if (next != null) {
        _flyTo(next.infractionPoint, _focusZoom);
      } else {
        _flyTo(_defaultCenter, _defaultZoom);
      }
    });

    return Container(
      color: VeraProbColors.background,
      child: Stack(
        children: [
          // ── Base Map ───────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: _defaultZoom,
              minZoom: 10,
              maxZoom: 18,
              backgroundColor: VeraProbColors.background,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: _buildTileUrl(),
                userAgentPackageName: 'com.veraprob.admin',
                tileBuilder: _darkTileBuilder,
              ),

              // Geofence circle (when a sanction is focused)
              if (_currentFocus?.geofenceCenter != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentFocus!.geofenceCenter!,
                      radius: _currentFocus!.geofenceRadiusMeters,
                      useRadiusInMeter: true,
                      color:
                          VeraProbColors.scheduled.withValues(alpha: 0.12),
                      borderColor:
                          VeraProbColors.scheduled.withValues(alpha: 0.6),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // Infraction marker with pulsing glow
              if (_currentFocus != null)
                MarkerLayer(
                  markers: [
                    _buildPulsingMarker(_currentFocus!.infractionPoint),
                  ],
                ),
            ],
          ),

          // ── Empty State (no selection) ──────────────────
          if (_currentFocus == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 40,
                    color: VeraProbColors.textDisabled.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Selecione uma sanção para\nlocalizar no mapa',
                    textAlign: TextAlign.center,
                    style: VeraProbTypography.bodySmall.copyWith(
                      color: VeraProbColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),

          // ── Map Legend ─────────────────────────────────
          if (_currentFocus != null)
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: VeraProbColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: VeraProbColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: VeraProbColors.critical,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Infração', style: VeraProbTypography.caption),
                    if (_currentFocus!.geofenceCenter != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: VeraProbColors.scheduled,
                            width: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('Geofence', style: VeraProbTypography.caption),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds a pulsing marker at [point] with a radial glow effect.
  Marker _buildPulsingMarker(LatLng point) {
    return Marker(
      point: point,
      width: 32,
      height: 32,
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          // Continuously pulse when focused
          if (!_animController.isAnimating) {
            _animController.repeat(reverse: true);
          }
          final opacity = _pulseAnimation.value;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  VeraProbColors.critical.withValues(alpha: opacity),
                  VeraProbColors.critical.withValues(alpha: opacity * 0.4),
                  VeraProbColors.critical.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: VeraProbColors.critical,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color:
                          VeraProbColors.critical.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _buildTileUrl() {
    if (AppConstants.mapTilerKey != 'get_your_own_key') {
      return AppConstants.mapTileUrl.replaceAll(
        '{key}',
        AppConstants.mapTilerKey,
      );
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  /// Applies a dark filter to standard OSM tiles when MapTiler is unavailable.
  static Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    if (kIsWeb) return tileWidget;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.8, 0.0, 0.0, 0.0, 40.0, //
        0.0, -0.8, 0.0, 0.0, 40.0, //
        0.0, 0.0, -0.8, 0.0, 50.0, //
        0.0, 0.0, 0.0, 1.0, 0.0, //
      ]),
      child: tileWidget,
    );
  }
}
