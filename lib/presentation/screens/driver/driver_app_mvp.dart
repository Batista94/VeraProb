import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/entities/raw_telemetry_ping.dart';
import 'package:busflow/state/providers/telemetry_providers.dart';

class DriverAppMvpScreen extends ConsumerStatefulWidget {
  const DriverAppMvpScreen({super.key});

  @override
  ConsumerState<DriverAppMvpScreen> createState() => _DriverAppMvpScreenState();
}

class _DriverAppMvpScreenState extends ConsumerState<DriverAppMvpScreen> {
  // Hardcoded for MVP Simulation
  final String _vehicleId = 'v1_MVP';
  final String _tripId = 'trip_MVP_001';

  bool _isEmitting = false;
  StreamSubscription<Position>? _positionStream;
  Position? _lastPosition;
  int _pingCount = 0;

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _toggleEmission() async {
    if (_isEmitting) {
      _stopEmission();
    } else {
      await _startEmission();
    }
  }

  Future<void> _startEmission() async {
    // 1. Request permissions (Requires configuration in AndroidManifest/Info.plist later)
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('Serviço de localização desativado.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Permissão negada.');
        return;
      }
    }

    // 2. Start listening
    setState(() {
      _isEmitting = true;
      _pingCount = 0;
    });

    final locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Emit every 10 meters changed
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            setState(() {
              _lastPosition = position;
              _pingCount++;
            });

            // 3. Emit Ping to the Purgatory
            final ping = RawTelemetryPing(
              vehicleId: _vehicleId,
              tripId: _tripId,
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              speed: position.speed,
              heading: position.heading,
              timestamp: position.timestamp,
            );

            ref.read(telemetryServiceProvider).pushPing(ping);
          },
        );
  }

  void _stopEmission() {
    _positionStream?.cancel();
    setState(() {
      _isEmitting = false;
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Emissor de Telemetria (Driver MVP)'),
        backgroundColor: BusFlowColors.surface,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Visual Indicator
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isEmitting
                      ? BusFlowColors.success.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                ),
                child: Icon(
                  _isEmitting ? Icons.satellite_alt : Icons.portable_wifi_off,
                  size: 64,
                  color: _isEmitting ? BusFlowColors.success : Colors.grey,
                ),
              ),
              const SizedBox(height: 32),

              // Status Text
              Text(
                _isEmitting ? 'TRANSMITINDO' : 'OFFLINE',
                style: BusFlowTypography.kpiValue.copyWith(
                  color: _isEmitting ? BusFlowColors.success : Colors.grey[600],
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              if (_isEmitting)
                Text(
                  '$_pingCount pings enviados',
                  style: BusFlowTypography.caption,
                ),
              const SizedBox(height: 48),

              // The Big Button
              SizedBox(
                width: double.infinity,
                height: 80,
                child: FilledButton(
                  onPressed: _toggleEmission,
                  style: FilledButton.styleFrom(
                    backgroundColor: _isEmitting
                        ? BusFlowColors.error
                        : BusFlowColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _isEmitting ? 'ENCERRAR VIAGEM' : 'INICIAR VIAGEM',
                    style: BusFlowTypography.sectionTitle.copyWith(
                      fontSize: 20,
                    ),
                  ),
                ),
              ),

              if (_lastPosition != null) ...[
                const SizedBox(height: 32),
                Text(
                  'Último GPS Lido:\nLat: ${_lastPosition!.latitude.toStringAsFixed(4)}\nLng: ${_lastPosition!.longitude.toStringAsFixed(4)}\nAcc: ${_lastPosition!.accuracy.toStringAsFixed(1)}m',
                  textAlign: TextAlign.center,
                  style: BusFlowTypography.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
