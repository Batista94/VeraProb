import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../state/providers/fleet_providers.dart';
import '../state/providers/sla_providers.dart';
import '../state/providers/auth_providers.dart';

/// Core metrics repository for the Stress Mode (Dev Only).
class PerformanceMetrics {
  double fps = 60.0;
  int rebuildsFleetMap = 0;
  int rebuildsKpiBar = 0;
  int rebuildsSidebar = 0;

  // Data-to-glass latency
  final Stopwatch globalStopwatch = Stopwatch()..start();
  int lastIngestionTickMs = 0;
  int lastLatencyMs = 0;

  void markIngestion() {
    lastIngestionTickMs = globalStopwatch.elapsedMilliseconds;
  }

  void markRender() {
    if (lastIngestionTickMs > 0) {
      lastLatencyMs = globalStopwatch.elapsedMilliseconds - lastIngestionTickMs;
      lastIngestionTickMs = 0; // Consume
    }
  }

  void resetRebuilds() {
    rebuildsFleetMap = 0;
    rebuildsKpiBar = 0;
    rebuildsSidebar = 0;
  }
}

final performanceMetricsProvider = Provider<PerformanceMetrics>((ref) {
  return PerformanceMetrics();
});

class FpsMetricsObserver extends StatefulWidget {
  final Widget child;

  const FpsMetricsObserver({super.key, required this.child});

  @override
  State<FpsMetricsObserver> createState() => _FpsMetricsObserverState();
}

class _FpsMetricsObserverState extends State<FpsMetricsObserver> {
  static const int _maxFrames = 60;
  final List<FrameTiming> _timings = [];

  void _onTimings(List<FrameTiming> timings) {
    if (!mounted) return;

    _timings.addAll(timings);
    if (_timings.length > _maxFrames) {
      _timings.removeRange(0, _timings.length - _maxFrames);
    }
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// A wrapper widget to count rebuilds for specific critical components.
class RebuildCounter extends ConsumerWidget {
  final String name;
  final Widget child;

  const RebuildCounter({super.key, required this.name, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.read(performanceMetricsProvider);
    if (name == 'FleetMap') {
      metrics.rebuildsFleetMap++;
      metrics.markRender();
    }
    if (name == 'KpiBar') metrics.rebuildsKpiBar++;
    if (name == 'Sidebar') metrics.rebuildsSidebar++;

    return child;
  }
}

/// The Heads-Up Display showing live performance metrics.
class PerformanceOverlayHud extends ConsumerStatefulWidget {
  const PerformanceOverlayHud({super.key});

  @override
  ConsumerState<PerformanceOverlayHud> createState() =>
      _PerformanceOverlayHudState();
}

class _PerformanceOverlayHudState extends ConsumerState<PerformanceOverlayHud>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<FrameTiming> _recentFrames = [];
  double _currentFps = 60.0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Ticker forces this specific overlay to rebuild frequently to update the FPS
    // without rebuilding the actual app.
    _ticker = createTicker((_) {
      setState(() {});
    })..start();
  }

  void _onTimings(List<FrameTiming> timings) {
    _recentFrames.addAll(timings);
    if (_recentFrames.length > 60) {
      _recentFrames.removeRange(0, _recentFrames.length - 60);
    }

    if (_recentFrames.isNotEmpty) {
      double totalDurationMs = 0;
      for (final timing in _recentFrames) {
        totalDurationMs += timing.totalSpan.inMicroseconds / 1000.0;
      }
      final avgDuration = totalDurationMs / _recentFrames.length;
      if (avgDuration > 0) {
        _currentFps = 1000 / avgDuration;
        if (_currentFps > 60) _currentFps = 60.0;
      }
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ref.read(performanceMetricsProvider);

    return Positioned(
      top: 60,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        width: 240,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
            ),
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Colors.greenAccent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🚀 OPERATIONAL STRESS MODE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text('FPS:        ${_currentFps.toStringAsFixed(1)}'),
              Text('Latency:    ${metrics.lastLatencyMs} ms'),
              const Divider(color: Colors.white24, height: 16),
              const Text(
                'TEST TOOLS (PHASE 9):',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    textStyle: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  ),
                  onPressed: () async {
                    final organizationId = ref.read(currentOrganizationIdProvider);
                    if (organizationId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Erro: Organization ID não encontrado.')),
                      );
                      return;
                    }

                    final simulation = ref.read(fleetSimulationProvider);
                    final simulationService = ref.read(sanctionSimulationServiceProvider);
                    
                    final trips = simulation.currentTrips;
                    final plate = trips.isNotEmpty 
                        ? (trips.first.vehiclePlate ?? 'ABC-1234') 
                        : 'ABC-1234';

                    await simulationService.simulateSpeedViolation(
                      organizationId: organizationId,
                      vehiclePlate: plate,
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Injetando VEL-01 para $plate na Fila Auditora...')),
                      );
                    }
                  },
                  child: const Text('TRIGGER VEL-01 (SPEED)'),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'INFO: Use a Fila Auditora para ver os resultados do Engine em < 1 min.',
                style: TextStyle(fontSize: 9, color: Colors.white38),
              ),
              const Divider(color: Colors.white24, height: 16),
              const Text(
                'REBUILDS:',
                style: TextStyle(color: Colors.white70),
              ),
              Text('Map: ${metrics.rebuildsFleetMap} | KPI: ${metrics.rebuildsKpiBar}'),
              Text('Sidebar: ${metrics.rebuildsSidebar}'),
            ],
          ),
        ),
      ),
    );
  }
}
