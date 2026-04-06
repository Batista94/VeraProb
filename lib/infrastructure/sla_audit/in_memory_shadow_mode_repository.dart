import 'package:veraprob/domain/sla_audit/shadow_mode_repository.dart';
import 'package:veraprob/domain/sla_audit/shadow_mode_simulation.dart';

/// In-memory implementation of [ShadowModeRepository] for testing.
class InMemoryShadowModeRepository implements ShadowModeRepository {
  final List<ShadowModeSimulation> _simulations = [];

  @override
  Future<void> save(ShadowModeSimulation simulation) async {
    _simulations.add(simulation);
  }

  @override
  Future<List<ShadowModeSimulation>> findByOrganization({
    required String organizationId,
    int limit = 10,
  }) async {
    final results =
        _simulations.where((s) => s.organizationId == organizationId).toList()
          ..sort((a, b) => b.generatedAtUtc.compareTo(a.generatedAtUtc));
    return results.take(limit).toList();
  }

  @override
  Future<ShadowModeSimulation?> findById({
    required String id,
    required String organizationId,
  }) async {
    try {
      return _simulations.firstWhere(
        (s) => s.id == id && s.organizationId == organizationId,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Test helpers ───────────────────────────────────────────────────────────
  List<ShadowModeSimulation> get all => List.unmodifiable(_simulations);
  int get count => _simulations.length;
  void clear() => _simulations.clear();
}
