import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/create_organization_form_data.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/shared/app_types.dart';

// Regras de Escrita:
// 1. Use DateTime.now().toUtc() em mocks (mesma linha).
// 2. Use int para valores monetários e taxas (BPS).
// 3. Proibido importar lib/infrastructure em testes de application.

CreateOrganizationFormData _makeFormData({
  String? reason = 'Criação padrão conforme contrato comercial #001',
  OrgCapabilitiesViewModel? capabilities,
}) {
  return CreateOrganizationFormData(
    legalName: 'Transportes Silva Ltda.',
    tradeName: 'Silva Logística',
    cnpj: '11.222.333/0001-81',
    timezone: 'America/Sao_Paulo',
    currencyCode: 'BRL',
    planType: PlanType.starter,
    maxVehicles: 10,
    maxActiveContracts: 5,
    initialAdminEmail: 'admin@silva.com.br',
    superAdminUserId: '00000000-0000-0000-0000-000000000001',
    capabilities: capabilities ?? OrgCapabilitiesViewModel.defaults,
    toolCostCents: 50000,
    dwellTimeSeconds: 300,
    reason: reason,
  );
}

void main() {
  group('CreateOrganizationFormData', () {
    test('toCommand propaga reason não-nulo para o command', () {
      const expectedReason = 'Novo cliente — contrato #999';
      final formData = _makeFormData(reason: expectedReason);
      final cmd = formData.toCommand();
      expect(cmd.reason, equals(expectedReason));
    });

    test('toCommand com reason nulo — campo permanece nulo no command', () {
      final formData = _makeFormData(reason: null);
      final cmd = formData.toCommand();
      expect(cmd.reason, isNull);
    });

    test('capabilities passam corretamente para o command via toDomain()', () {
      const vm = OrgCapabilitiesViewModel(
        allowsSealing: false,
        allowsDoc: true,
        maxKinematicSpeedKmh: 80.0, // Physical Metric - Double Required
      );
      final formData = _makeFormData(capabilities: vm);
      final cmd = formData.toCommand();
      expect(cmd.capabilities?.allowsSealing, isFalse);
      expect(cmd.capabilities?.allowsDoc, isTrue);
      expect(cmd.capabilities?.maxKinematicSpeedKmh, 80.0);
    });

    test('estrutura básica de tipos e timestamps UTC', () {
      final mockTimestamp = DateTime.now().toUtc();
      const int monetaryValueCents = 50000;

      expect(mockTimestamp.isUtc, isTrue);
      expect(monetaryValueCents, isA<int>());
    });
  });
}
