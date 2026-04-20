import 'package:veraprob/domain/sla_audit/smart_defaults.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';

/// Static catalog of system-provided SLA template presets.
///
/// These presets live in application memory (not persisted in the database)
/// to avoid RLS complexity and DB pollution. They are read-only and
/// identifiable by their `preset:` ID prefix.
abstract final class SlaTemplatePresets {
  /// Prefix used to distinguish system presets from org-owned templates.
  static const idPrefix = 'preset:';

  /// Returns true if [id] belongs to a system preset (not org-owned).
  static bool isPreset(String id) => id.startsWith(idPrefix);

  /// Returns all system presets, one per non-custom [TransportVertical].
  static List<SlaTemplate> systemPresets() {
    return _cache;
  }

  /// Returns a single preset by [id], or null if not found.
  static SlaTemplate? findById(String id) {
    if (!isPreset(id)) return null;
    return _cacheMap[id];
  }

  // ── Internal cache (computed once) ──────────────────────────

  static final List<SlaTemplate> _cache = _buildPresets();
  static final Map<String, SlaTemplate> _cacheMap = {
    for (final p in _cache) p.id: p,
  };

  static List<SlaTemplate> _buildPresets() {
    final verticals = TransportVertical.values
        .where((v) => v != TransportVertical.custom)
        .toList();

    return verticals.map((vertical) {
      final penalties = SmartDefaults.defaultsFor(vertical);
      return SlaTemplate.reconstitute(
        id: '$idPrefix${vertical.name}',
        organizationId: 'system',
        name: vertical.label,
        description: _descriptionFor(vertical),
        vertical: vertical,
        penalties: penalties,
        createdAt: DateTime.utc(2026, 1, 1),
      );
    }).toList();
  }

  static String _descriptionFor(TransportVertical vertical) {
    return switch (vertical) {
      TransportVertical.fretamento =>
        'Transporte de passageiros com tolerância moderada e penalidades equilibradas.',
      TransportVertical.cargaSeca =>
        'Transporte de carga seca com tolerâncias amplas e penalidades reduzidas.',
      TransportVertical.cargaRefrigerada =>
        'Carga refrigerada com penalidades severas por atraso e no-show.',
      TransportVertical.transferenciaFuncionarios =>
        'Transferência de funcionários com pontualidade rigorosa.',
      TransportVertical.escolar =>
        'Transporte escolar com as penalidades mais severas do sistema.',
      TransportVertical.custom => 'Personalizado',
    };
  }
}
