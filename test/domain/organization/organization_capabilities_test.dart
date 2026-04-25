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
  });
}
