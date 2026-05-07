import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/application/org_capabilities_view_model.dart';
import 'package:veraprob/features/super_admin/application/org_preset_view_model.dart';

// Regras de Escrita:
// 1. Use DateTime.now().toUtc() em mocks (mesma linha).
// 2. Use int para valores monetários e taxas (BPS).
// 3. Proibido importar lib/infrastructure em testes de application.

void main() {
  group('OrgPresetViewModel', () {
    test('labels map is non-empty and contains known presets', () {
      final labels = OrgPresetViewModel.labels;

      expect(labels, isNotEmpty);
      expect(labels.containsKey('VIACAO'), isTrue);
      expect(labels.containsKey('CARGA'), isTrue);
    });

    test('labels values are human-readable strings', () {
      final labels = OrgPresetViewModel.labels;

      for (final entry in labels.entries) {
        expect(entry.key, isNotEmpty);
        expect(entry.value, isNotEmpty);
      }
    });

    test('resolveCapabilities returns defaults when preset is null', () {
      final caps = OrgPresetViewModel.resolveCapabilities(null);
      expect(caps, equals(OrgCapabilitiesViewModel.defaults));
    });

    test('resolveCapabilities returns defaults for unknown preset', () {
      final caps = OrgPresetViewModel.resolveCapabilities('UNKNOWN_PRESET');
      expect(caps, equals(OrgCapabilitiesViewModel.defaults));
    });

    test('resolveCapabilities(VIACAO) disables sealing and loading', () {
      final caps = OrgPresetViewModel.resolveCapabilities('VIACAO');

      // Viação preset: passenger transport — no sealing/loading
      expect(caps.allowsSealing, isFalse);
      expect(caps.allowsLoading, isFalse);
      expect(caps.allowsCargoCheck, isFalse);
      // Incidents and docs remain enabled
      expect(caps.allowsIncident, isTrue);
      expect(caps.allowsDoc, isTrue);
      expect(caps.smartClassify, isTrue);
      // Speed limit is set for viação
      expect(caps.maxKinematicSpeedKmh, isNotNull);
    });

    test('resolveCapabilities(CARGA) enables all cargo capabilities', () {
      final caps = OrgPresetViewModel.resolveCapabilities('CARGA');

      expect(caps.allowsSealing, isTrue);
      expect(caps.allowsLoading, isTrue);
      expect(caps.allowsCargoCheck, isTrue);
      expect(caps.allowsIncident, isTrue);
      expect(caps.allowsDoc, isTrue);
      expect(caps.smartClassify, isTrue);
      expect(caps.maxKinematicSpeedKmh, isNotNull);
    });

    test(
      'resolveCapabilities returns OrgCapabilitiesViewModel — not a domain type',
      () {
        // Compile-time: return type is OrgCapabilitiesViewModel, proven by usage
        // of ViewModel-specific fields without importing OrgCapabilities.
        final caps = OrgPresetViewModel.resolveCapabilities('CARGA');

        expect(caps, isA<OrgCapabilitiesViewModel>());
        expect(caps.allowsSealing, isA<bool>());
      },
    );

    test('different presets resolve to different capabilities', () {
      final viacao = OrgPresetViewModel.resolveCapabilities('VIACAO');
      final carga = OrgPresetViewModel.resolveCapabilities('CARGA');

      // They should differ on sealing (viação=false, carga=true)
      expect(viacao == carga, isFalse);
    });
  });
}
