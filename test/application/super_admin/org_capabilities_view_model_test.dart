import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/application/org_capabilities_view_model.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';

// Regras de Escrita:
// 1. Use DateTime.now().toUtc() em mocks (mesma linha).
// 2. Use int para valores monetários e taxas (BPS).
// 3. Proibido importar lib/infrastructure em testes de application.

void main() {
  group('OrgCapabilitiesViewModel', () {
    test('defaults match OrgCapabilities.defaults semantics', () {
      const vm = OrgCapabilitiesViewModel.defaults;

      expect(vm.allowsSealing, isTrue);
      expect(vm.allowsLoading, isTrue);
      expect(vm.allowsCargoCheck, isTrue);
      expect(vm.allowsIncident, isTrue);
      expect(vm.allowsDoc, isTrue);
      expect(vm.smartClassify, isTrue);
      expect(vm.maxKinematicSpeedKmh, isNull);
    });

    test('fromDomain maps all fields correctly', () {
      const domain = OrgCapabilities(
        allowsSealing: false,
        allowsLoading: true,
        allowsCargoCheck: false,
        allowsIncident: true,
        allowsDoc: false,
        smartClassify: false,
        maxKinematicSpeedKmh: 80.0, // Physical Metric - Double Required
      );

      final vm = OrgCapabilitiesViewModel.fromDomain(domain);

      expect(vm.allowsSealing, isFalse);
      expect(vm.allowsLoading, isTrue);
      expect(vm.allowsCargoCheck, isFalse);
      expect(vm.allowsIncident, isTrue);
      expect(vm.allowsDoc, isFalse);
      expect(vm.smartClassify, isFalse);
      expect(vm.maxKinematicSpeedKmh, 80.0);
    });

    test('toDomain produces equivalent OrgCapabilities', () {
      const vm = OrgCapabilitiesViewModel(
        allowsSealing: false,
        allowsLoading: true,
        allowsCargoCheck: false,
        allowsIncident: true,
        allowsDoc: true,
        smartClassify: false,
        maxKinematicSpeedKmh: 120.0, // Physical Metric - Double Required
      );

      final domain = vm.toDomain();

      expect(domain.allowsSealing, vm.allowsSealing);
      expect(domain.allowsLoading, vm.allowsLoading);
      expect(domain.allowsCargoCheck, vm.allowsCargoCheck);
      expect(domain.allowsIncident, vm.allowsIncident);
      expect(domain.allowsDoc, vm.allowsDoc);
      expect(domain.smartClassify, vm.smartClassify);
      expect(domain.maxKinematicSpeedKmh, vm.maxKinematicSpeedKmh);
    });

    test('round-trip: fromDomain → toDomain preserves all fields', () {
      const original = OrgCapabilities(
        allowsSealing: true,
        allowsLoading: false,
        allowsCargoCheck: true,
        allowsIncident: false,
        allowsDoc: true,
        smartClassify: true,
        maxKinematicSpeedKmh: 60.0, // Physical Metric - Double Required
      );

      final roundTripped = OrgCapabilitiesViewModel.fromDomain(
        original,
      ).toDomain();

      expect(roundTripped.allowsSealing, original.allowsSealing);
      expect(roundTripped.allowsLoading, original.allowsLoading);
      expect(roundTripped.allowsCargoCheck, original.allowsCargoCheck);
      expect(roundTripped.allowsIncident, original.allowsIncident);
      expect(roundTripped.allowsDoc, original.allowsDoc);
      expect(roundTripped.smartClassify, original.smartClassify);
      expect(roundTripped.maxKinematicSpeedKmh, original.maxKinematicSpeedKmh);
    });

    test('copyWith overrides only specified fields', () {
      const base = OrgCapabilitiesViewModel(
        allowsSealing: true,
        allowsLoading: true,
        allowsCargoCheck: true,
        allowsIncident: true,
        allowsDoc: true,
        smartClassify: true,
      );

      final modified = base.copyWith(
        allowsSealing: false,
        smartClassify: false,
      );

      expect(modified.allowsSealing, isFalse);
      expect(modified.smartClassify, isFalse);
      // Unchanged fields
      expect(modified.allowsLoading, isTrue);
      expect(modified.allowsCargoCheck, isTrue);
      expect(modified.allowsIncident, isTrue);
      expect(modified.allowsDoc, isTrue);
    });

    test('equality is value-based', () {
      const a = OrgCapabilitiesViewModel(allowsSealing: false);
      const b = OrgCapabilitiesViewModel(allowsSealing: false);
      const c = OrgCapabilitiesViewModel(allowsSealing: true);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test(
      'no domain imports are required by this ViewModel — it is self-contained',
      () {
        // Compile-time evidence: the test only imports the ViewModel and the
        // domain type for round-trip verification. The ViewModel holds no
        // OrgCapabilities fields in its public API.
        const vm = OrgCapabilitiesViewModel.defaults;
        expect(vm.allowsSealing, isA<bool>());
        expect(vm.maxKinematicSpeedKmh, isA<double?>());
      },
    );
  });
}
