import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/super_admin/org_vertical_preset.dart';

void main() {
  group('OrgVerticalPreset — constants', () {
    test('VIACAO constant value', () {
      expect(OrgVerticalPreset.viacao, 'VIACAO');
    });

    test('CARGA constant value', () {
      expect(OrgVerticalPreset.carga, 'CARGA');
    });

    test('labels map contains both presets', () {
      expect(OrgVerticalPreset.labels, containsPair('VIACAO', isNotEmpty));
      expect(OrgVerticalPreset.labels, containsPair('CARGA', isNotEmpty));
    });

    test('defaults map contains both presets', () {
      expect(OrgVerticalPreset.defaults.keys, containsAll(['VIACAO', 'CARGA']));
    });
  });

  group('OrgVerticalPreset — VIACAO capabilities (INV-14)', () {
    late OrgCapabilities viacao;

    setUpAll(() {
      viacao = OrgVerticalPreset.defaults[OrgVerticalPreset.viacao]!;
    });

    test('allowsSealing = false (passenger transit has no cargo sealing)', () {
      expect(viacao.allowsSealing, isFalse);
    });

    test('allowsLoading = false', () {
      expect(viacao.allowsLoading, isFalse);
    });

    test('allowsCargoCheck = false', () {
      expect(viacao.allowsCargoCheck, isFalse);
    });

    test('allowsIncident = true', () {
      expect(viacao.allowsIncident, isTrue);
    });

    test('allowsDoc = true', () {
      expect(viacao.allowsDoc, isTrue);
    });

    test('smartClassify = true', () {
      expect(viacao.smartClassify, isTrue);
    });

    test('maxKinematicSpeedKmh = 80.0 (INV-12: physical metric, double)', () {
      expect(viacao.maxKinematicSpeedKmh, 80.0);
      expect(viacao.maxKinematicSpeedKmh, isA<double>());
    });

    test('hiddenCategories includes sealing and loading categories', () {
      final hidden = viacao.hiddenCategories;
      expect(hidden, containsAll(['lacre', 'chk_saida', 'carregamento']));
    });

    test('hiddenCategories does NOT hide incidente or doc', () {
      final hidden = viacao.hiddenCategories;
      expect(hidden, isNot(contains('incidente')));
      expect(hidden, isNot(contains('doc')));
    });
  });

  group('OrgVerticalPreset — CARGA capabilities (INV-14)', () {
    late OrgCapabilities carga;

    setUpAll(() {
      carga = OrgVerticalPreset.defaults[OrgVerticalPreset.carga]!;
    });

    test('allowsSealing = true', () {
      expect(carga.allowsSealing, isTrue);
    });

    test('allowsLoading = true', () {
      expect(carga.allowsLoading, isTrue);
    });

    test('allowsCargoCheck = true', () {
      expect(carga.allowsCargoCheck, isTrue);
    });

    test('allowsIncident = true', () {
      expect(carga.allowsIncident, isTrue);
    });

    test('allowsDoc = true', () {
      expect(carga.allowsDoc, isTrue);
    });

    test('smartClassify = true', () {
      expect(carga.smartClassify, isTrue);
    });

    test('maxKinematicSpeedKmh = 120.0 (INV-12: physical metric, double)', () {
      expect(carga.maxKinematicSpeedKmh, 120.0);
      expect(carga.maxKinematicSpeedKmh, isA<double>());
    });

    test('hiddenCategories is empty (all categories visible for carga)', () {
      expect(carga.hiddenCategories, isEmpty);
    });
  });

  group('OrgVerticalPreset — preset isolation (INV-22)', () {
    test('VIACAO and CARGA are distinct objects', () {
      final v = OrgVerticalPreset.defaults[OrgVerticalPreset.viacao]!;
      final c = OrgVerticalPreset.defaults[OrgVerticalPreset.carga]!;
      expect(v, isNot(equals(c)));
    });

    test('VIACAO speed < CARGA speed', () {
      final vSpeed = OrgVerticalPreset
          .defaults[OrgVerticalPreset.viacao]!
          .maxKinematicSpeedKmh!;
      final cSpeed = OrgVerticalPreset
          .defaults[OrgVerticalPreset.carga]!
          .maxKinematicSpeedKmh!;
      expect(vSpeed, lessThan(cSpeed));
    });

    test('unknown preset key returns null (no silent default)', () {
      expect(OrgVerticalPreset.defaults['UNKNOWN'], isNull);
    });

    test('labels map does not contain unknown keys', () {
      expect(OrgVerticalPreset.labels.containsKey('UNKNOWN'), isFalse);
    });
  });

  group('OrgVerticalPreset — toJson/fromJson roundtrip via OrgCapabilities', () {
    test('VIACAO preset survives toJson/fromJson', () {
      final original = OrgVerticalPreset.defaults[OrgVerticalPreset.viacao]!;
      final restored = OrgCapabilities.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    test('CARGA preset survives toJson/fromJson', () {
      final original = OrgVerticalPreset.defaults[OrgVerticalPreset.carga]!;
      final restored = OrgCapabilities.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    test(
      'maxKinematicSpeedKmh is preserved as double in JSON (not truncated to int)',
      () {
        final caps = OrgVerticalPreset.defaults[OrgVerticalPreset.viacao]!;
        final json = caps.toJson();
        expect(json['max_kinematic_speed_kmh'], isA<double>());
        expect(json['max_kinematic_speed_kmh'], 80.0);
      },
    );
  });
}
