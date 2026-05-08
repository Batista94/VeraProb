// TDD anchor — Phase 10 Workstream 1 (ARCHITECT)
// Fails until lib/domain/admin/org_capabilities.dart is created.
// INV-14: capability flags, not enum — agnostic core, no vertical leak.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';

void main() {
  group('OrgCapabilities — defaults (NULL caps = all visible)', () {
    test('defaults show zero hidden categories', () {
      const caps = OrgCapabilities.defaults;
      expect(caps.hiddenCategories, isEmpty);
    });

    test('defaults have smartClassify enabled', () {
      const caps = OrgCapabilities.defaults;
      expect(caps.smartClassify, isTrue);
    });
  });

  group('OrgCapabilities — sealing restriction', () {
    test('allows_sealing=false hides lacre and chk_saida', () {
      const caps = OrgCapabilities(allowsSealing: false);
      expect(caps.hiddenCategories, containsAll(['lacre', 'chk_saida']));
    });

    test('allows_sealing=false does NOT hide carregamento', () {
      const caps = OrgCapabilities(allowsSealing: false);
      expect(caps.hiddenCategories, isNot(contains('carregamento')));
    });
  });

  group('OrgCapabilities — loading restriction', () {
    test('allows_loading=false hides carregamento only', () {
      const caps = OrgCapabilities(allowsLoading: false);
      expect(caps.hiddenCategories, containsAll(['carregamento']));
      expect(caps.hiddenCategories, isNot(contains('lacre')));
    });
  });

  group('OrgCapabilities — full restriction', () {
    test('multiple restrictions accumulate correctly', () {
      const caps = OrgCapabilities(
        allowsSealing: false,
        allowsLoading: false,
        allowsIncident: false,
        allowsDoc: false,
      );
      expect(
        caps.hiddenCategories,
        containsAll(['lacre', 'chk_saida', 'carregamento', 'incidente', 'doc']),
      );
    });

    test('estado and outros are never hidden', () {
      const caps = OrgCapabilities(
        allowsSealing: false,
        allowsLoading: false,
        allowsIncident: false,
        allowsDoc: false,
      );
      expect(caps.hiddenCategories, isNot(contains('estado')));
      expect(caps.hiddenCategories, isNot(contains('outros')));
    });
  });

  group('OrgCapabilities.fromJson', () {
    test('all true = no hidden categories', () {
      final caps = OrgCapabilities.fromJson({
        'allows_sealing': true,
        'allows_loading': true,
        'allows_cargo_check': true,
        'allows_incident': true,
        'allows_doc': true,
        'smart_classify': true,
      });
      expect(caps.hiddenCategories, isEmpty);
      expect(caps.smartClassify, isTrue);
    });

    test('allows_sealing=false hides sealing categories', () {
      final caps = OrgCapabilities.fromJson({'allows_sealing': false});
      expect(caps.hiddenCategories, containsAll(['lacre', 'chk_saida']));
    });

    test(
      'empty map defaults all to true (safe migration — no client breakage)',
      () {
        final caps = OrgCapabilities.fromJson({});
        expect(caps.hiddenCategories, isEmpty);
        expect(caps.smartClassify, isTrue);
      },
    );

    test('smart_classify=false disables GPS auto-classify', () {
      final caps = OrgCapabilities.fromJson({'smart_classify': false});
      expect(caps.smartClassify, isFalse);
      expect(
        caps.hiddenCategories,
        isEmpty,
      ); // smartClassify doesn't hide menu items
    });

    test('maxKinematicSpeedKmh parsed as double from int JSON value', () {
      final caps = OrgCapabilities.fromJson({'max_kinematic_speed_kmh': 80});
      expect(caps.maxKinematicSpeedKmh, 80.0);
      expect(caps.maxKinematicSpeedKmh, isA<double>());
    });

    test('maxKinematicSpeedKmh parsed as double from double JSON value', () {
      final caps = OrgCapabilities.fromJson({'max_kinematic_speed_kmh': 88.5});
      expect(caps.maxKinematicSpeedKmh, 88.5);
      expect(caps.maxKinematicSpeedKmh, isA<double>());
    });

    test(
      'maxKinematicSpeedKmh absent from JSON → null (not truncated to 0)',
      () {
        final caps = OrgCapabilities.fromJson({});
        expect(caps.maxKinematicSpeedKmh, isNull);
      },
    );
  });

  group('OrgCapabilities.toJson (INV-12: physical metric as double)', () {
    test('default caps serializes flags correctly', () {
      const caps = OrgCapabilities.defaults;
      final json = caps.toJson();
      expect(json['allows_sealing'], isTrue);
      expect(json['allows_loading'], isTrue);
      expect(json['allows_cargo_check'], isTrue);
      expect(json['allows_incident'], isTrue);
      expect(json['allows_doc'], isTrue);
      expect(json['smart_classify'], isTrue);
      expect(json.containsKey('max_kinematic_speed_kmh'), isFalse);
    });

    test('maxKinematicSpeedKmh included in JSON when set', () {
      const caps = OrgCapabilities(maxKinematicSpeedKmh: 120.0);
      final json = caps.toJson();
      expect(json['max_kinematic_speed_kmh'], 120.0);
      expect(json['max_kinematic_speed_kmh'], isA<double>());
    });

    test('maxKinematicSpeedKmh absent from JSON when null', () {
      const caps = OrgCapabilities();
      final json = caps.toJson();
      expect(json.containsKey('max_kinematic_speed_kmh'), isFalse);
    });

    test('fromJson(toJson()) roundtrip preserves all fields', () {
      const original = OrgCapabilities(
        allowsSealing: false,
        allowsLoading: true,
        allowsCargoCheck: false,
        allowsIncident: true,
        allowsDoc: false,
        smartClassify: false,
        maxKinematicSpeedKmh: 95.5,
      );
      final restored = OrgCapabilities.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    test('roundtrip with null maxKinematicSpeedKmh', () {
      const original = OrgCapabilities(allowsSealing: false);
      final restored = OrgCapabilities.fromJson(original.toJson());
      expect(restored, equals(original));
      expect(restored.maxKinematicSpeedKmh, isNull);
    });
  });

  group('OrgCapabilities.copyWith', () {
    test('copyWith returns same values when no args passed', () {
      const original = OrgCapabilities(
        allowsSealing: false,
        maxKinematicSpeedKmh: 80.0,
      );
      final copy = original.copyWith();
      expect(copy, equals(original));
    });

    test('copyWith overrides single field', () {
      const original = OrgCapabilities(allowsSealing: false);
      final copy = original.copyWith(allowsSealing: true);
      expect(copy.allowsSealing, isTrue);
      expect(copy.allowsLoading, original.allowsLoading);
    });

    test('copyWith overrides maxKinematicSpeedKmh', () {
      const original = OrgCapabilities(maxKinematicSpeedKmh: 80.0);
      final copy = original.copyWith(maxKinematicSpeedKmh: 120.0);
      expect(copy.maxKinematicSpeedKmh, 120.0);
      expect(original.maxKinematicSpeedKmh, 80.0); // original unchanged
    });

    test('copyWith does not mutate original', () {
      const original = OrgCapabilities(
        allowsSealing: false,
        maxKinematicSpeedKmh: 80.0,
      );
      original.copyWith(allowsSealing: true, maxKinematicSpeedKmh: 99.0);
      expect(original.allowsSealing, isFalse);
      expect(original.maxKinematicSpeedKmh, 80.0);
    });
  });

  group('OrgCapabilities — Equatable (INV-7)', () {
    test('identical instances are equal', () {
      const a = OrgCapabilities(
        allowsSealing: false,
        maxKinematicSpeedKmh: 80.0,
      );
      const b = OrgCapabilities(
        allowsSealing: false,
        maxKinematicSpeedKmh: 80.0,
      );
      expect(a, equals(b));
    });

    test('instances differ on maxKinematicSpeedKmh', () {
      const a = OrgCapabilities(maxKinematicSpeedKmh: 80.0);
      const b = OrgCapabilities(maxKinematicSpeedKmh: 120.0);
      expect(a, isNot(equals(b)));
    });

    test('instance with null maxKinematicSpeedKmh != instance with value', () {
      const a = OrgCapabilities();
      const b = OrgCapabilities(maxKinematicSpeedKmh: 80.0);
      expect(a, isNot(equals(b)));
    });

    test('defaults == OrgCapabilities() with no args', () {
      expect(OrgCapabilities.defaults, equals(const OrgCapabilities()));
    });
  });
}
