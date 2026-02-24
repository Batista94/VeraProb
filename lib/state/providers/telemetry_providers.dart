import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/data/services/telemetry_service.dart';

/// Provider for the Telemetry Service (Bridge)
final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  final service = TelemetryService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Exposes the stream of clean positions
final cleanPositionsStreamProvider = StreamProvider((ref) {
  return ref.watch(telemetryServiceProvider).cleanPositionsStream;
});
