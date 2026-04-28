import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/super_admin/org_preset_view_model.dart';

// Regras de Escrita:
// 1. Use DateTime.now().toUtc() em mocks (mesma linha).
// 2. Use int para valores monetários e taxas (BPS).
// 3. Proibido importar lib/infrastructure em testes de application.

void main() {
  group('OrgPreset como Template (não estado bloqueante)', () {
    test(
      'VM retornada por resolveCapabilities é mutável via copyWith (preset não bloqueia edição)',
      () {
        // Viação preset: allowsSealing = false
        final viacaoVm = OrgPresetViewModel.resolveCapabilities('VIACAO');
        expect(viacaoVm.allowsSealing, isFalse);

        // O SuperAdmin adiciona Lacre por contrato específico → copyWith não conflita
        final customized = viacaoVm.copyWith(allowsSealing: true);
        expect(customized.allowsSealing, isTrue);

        // Imutabilidade: o preset original não foi alterado
        final originalAgain = OrgPresetViewModel.resolveCapabilities('VIACAO');
        expect(originalAgain.allowsSealing, isFalse);
      },
    );

    test(
      'isCustomized: VM igual ao template → false (preset não foi alterado)',
      () {
        final template = OrgPresetViewModel.resolveCapabilities('VIACAO');
        expect(template.isCustomized(template), isFalse);
      },
    );

    test(
      'isCustomized: VM com allowsSealing=true vs template Viação (false) → true',
      () {
        final template = OrgPresetViewModel.resolveCapabilities('VIACAO');
        final customized = template.copyWith(allowsSealing: true);
        expect(customized.isCustomized(template), isTrue);
      },
    );

    test(
      'isCustomized: VM com cargo check toggled vs template Viação → true',
      () {
        final template = OrgPresetViewModel.resolveCapabilities('VIACAO');
        final customized = template.copyWith(allowsCargoCheck: true);
        expect(customized.isCustomized(template), isTrue);
      },
    );

    test('isCustomized: defaults vm vs defaults template → false', () {
      const vm = OrgCapabilitiesViewModel.defaults;
      expect(vm.isCustomized(OrgCapabilitiesViewModel.defaults), isFalse);
    });

    test(
      'isCustomized: speed alterada vs template com speed diferente → true',
      () {
        final template = OrgPresetViewModel.resolveCapabilities('VIACAO');
        // Viação tem maxKinematicSpeedKmh = 80.0 — SuperAdmin muda para 60
        final customized = template.copyWith(maxKinematicSpeedKmh: 60.0);
        expect(customized.isCustomized(template), isTrue);
      },
    );

    test(
      'resolveCapabilities sem preset (null) → defaults, isCustomized sempre false vs defaults',
      () {
        final vm = OrgPresetViewModel.resolveCapabilities(null);
        expect(vm.isCustomized(OrgCapabilitiesViewModel.defaults), isFalse);
      },
    );
  });

  group('Imutabilidade de preset constants', () {
    test('Preset VIACAO sempre retorna a mesma configuração', () {
      final a = OrgPresetViewModel.resolveCapabilities('VIACAO');
      final b = OrgPresetViewModel.resolveCapabilities('VIACAO');

      // Estruturalmente iguais (value equality via ==)
      expect(a, equals(b));
    });

    test('Preset CARGA sempre retorna a mesma configuração', () {
      final a = OrgPresetViewModel.resolveCapabilities('CARGA');
      final b = OrgPresetViewModel.resolveCapabilities('CARGA');
      expect(a, equals(b));
    });
  });
}
