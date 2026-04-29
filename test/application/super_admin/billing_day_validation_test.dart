import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/super_admin/create_organization_form_data.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  CreateOrganizationFormData form({int? billingDay}) =>
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
        billingDay: billingDay,
      );

  group('billing_day validation in CreateOrganizationFormData.toCommand()', () {
    test('null passes — field is optional', () {
      expect(() => form(billingDay: null).toCommand(), returnsNormally);
    });

    test('1 passes — lower bound', () {
      expect(() => form(billingDay: 1).toCommand(), returnsNormally);
    });

    test('28 passes — upper bound', () {
      expect(() => form(billingDay: 28).toCommand(), returnsNormally);
    });

    test('0 throws IntegrityException', () {
      expect(
        () => form(billingDay: 0).toCommand(),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('29 throws IntegrityException — no month has guaranteed day 29', () {
      expect(
        () => form(billingDay: 29).toCommand(),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('30 throws IntegrityException', () {
      expect(
        () => form(billingDay: 30).toCommand(),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('31 throws IntegrityException', () {
      expect(
        () => form(billingDay: 31).toCommand(),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('-1 throws IntegrityException', () {
      expect(
        () => form(billingDay: -1).toCommand(),
        throwsA(isA<IntegrityException>()),
      );
    });
  });
}
