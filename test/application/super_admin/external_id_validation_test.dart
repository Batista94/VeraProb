import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/super_admin/create_organization_form_data.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  CreateOrganizationFormData form({String? externalId}) =>
      CreateOrganizationFormData(
        legalName: 'Transportes Silva Ltda.',
        tradeName: 'Silva Logística',
        cnpj: '11222333000181',
        timezone: 'America/Sao_Paulo',
        currencyCode: 'BRL',
        planType: PlanType.starter,
        maxVehicles: 50,
        maxActiveContracts: 10,
        initialAdminEmail: 'admin@empresa.com.br',
        superAdminUserId: 'super-admin-uuid-123',
        toolCostCents: 50000,
        reason: 'Motivo válido para o log de auditoria',
        externalId: externalId,
      );

  group('external_id validation in CreateOrganizationFormData.toCommand()', () {
    test('null passes — field is optional', () {
      expect(() => form(externalId: null).toCommand(), returnsNormally);
    });

    test('exactly 100 chars passes', () {
      final id = 'a' * 100;
      expect(() => form(externalId: id).toCommand(), returnsNormally);
    });

    test('101 chars throws IntegrityException', () {
      final id = 'a' * 101;
      expect(
        () => form(externalId: id).toCommand(),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('255 chars throws IntegrityException — buffer overflow guard', () {
      final id = 'x' * 255;
      expect(
        () => form(externalId: id).toCommand(),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('SQL injection chars treated as opaque — passes when ≤ 100 chars', () {
      const id = "'; DROP TABLE organizations;--";
      expect(() => form(externalId: id).toCommand(), returnsNormally);
    });

    test('empty string passes — treated as explicit empty ref', () {
      expect(() => form(externalId: '').toCommand(), returnsNormally);
    });
  });
}
