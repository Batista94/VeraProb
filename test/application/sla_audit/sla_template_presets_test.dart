import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/sla_template_presets.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';

void main() {
  group('SlaTemplatePresets', () {
    test('retorna um preset por vertical não-custom', () {
      final presets = SlaTemplatePresets.systemPresets();
      final nonCustomVerticals = TransportVertical.values
          .where((v) => v != TransportVertical.custom)
          .toList();

      expect(presets.length, nonCustomVerticals.length);
    });

    test('todos os IDs começam com preset:', () {
      for (final p in SlaTemplatePresets.systemPresets()) {
        expect(p.id, startsWith('preset:'));
        expect(SlaTemplatePresets.isPreset(p.id), isTrue);
      }
    });

    test('nenhum ID duplicado', () {
      final ids = SlaTemplatePresets.systemPresets().map((p) => p.id).toSet();
      expect(ids.length, SlaTemplatePresets.systemPresets().length);
    });

    test('cada preset tem vertical não-null', () {
      for (final p in SlaTemplatePresets.systemPresets()) {
        expect(p.vertical, isNotNull);
      }
    });

    test('cada preset tem nome não-vazio', () {
      for (final p in SlaTemplatePresets.systemPresets()) {
        expect(p.name, isNotEmpty);
      }
    });

    test('cada preset tem penalties com valores válidos', () {
      for (final p in SlaTemplatePresets.systemPresets()) {
        expect(p.penalties.noShowPenaltyBps, greaterThanOrEqualTo(10000));
        expect(p.penalties.delayPenaltyPerMinute.cents, greaterThan(0));
        expect(p.penalties.downgradePenaltyFlat.cents, greaterThan(0));
      }
    });

    test('findById retorna preset existente', () {
      final preset = SlaTemplatePresets.findById('preset:fretamento');

      expect(preset, isNotNull);
      expect(preset!.vertical, TransportVertical.fretamento);
    });

    test('findById retorna null para ID inexistente', () {
      expect(SlaTemplatePresets.findById('preset:nope'), isNull);
    });

    test('findById retorna null para ID sem prefixo preset:', () {
      expect(SlaTemplatePresets.findById('fretamento'), isNull);
    });

    test('isPreset diferencia presets de org templates', () {
      expect(SlaTemplatePresets.isPreset('preset:fretamento'), isTrue);
      expect(SlaTemplatePresets.isPreset('uuid-123-456'), isFalse);
    });
  });
}
