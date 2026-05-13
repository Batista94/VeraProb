import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/super_admin/cnpj_company_data.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  group('CnpjCompanyData (Forensic Audit)', () {
    const validCnpjMasked = '11.222.333/0001-81';
    const validCnpjRaw = '11222333000181';

    // ── 1. Constructor & Normalisation (Security Integrity) ─────────────────
    group('constructor & normalisation', () {
      test('normalises masked CNPJ to raw digits only', () {
        final data = CnpjCompanyData(cnpj: validCnpjMasked);
        expect(
          data.cnpj,
          equals(validCnpjRaw),
          reason: 'CNPJ must be stored as digits only for security indexing.',
        );
      });

      test('removes malicious characters/injections from CNPJ string', () {
        final data = CnpjCompanyData(
          cnpj: "11.222.333/0001-81'; DROP TABLE users;",
        );
        expect(
          data.cnpj,
          equals(validCnpjRaw),
          reason: 'Non-numeric injection payloads must be stripped.',
        );
      });

      test('removes whitespace from CNPJ', () {
        final data = CnpjCompanyData(cnpj: '  11222333000181  ');
        expect(data.cnpj, equals(validCnpjRaw));
      });

      test(
        'throws IntegrityException if CNPJ is empty or contains no digits (TDD Compliance)',
        () {
          // This test ensures we follow INV-18 (rejecting garbage)
          expect(
            () => CnpjCompanyData(cnpj: ''),
            throwsA(isA<IntegrityException>()),
          );
          expect(
            () => CnpjCompanyData(cnpj: 'abc-def'),
            throwsA(isA<IntegrityException>()),
          );
        },
      );
    });

    // ── 2. Serialization (JSON Integrity) ────────────────────────────────────
    group('serialization', () {
      test(
        'fromJson maps international and brazilian field names correctly',
        () {
          final json = {
            'cnpj': validCnpjRaw,
            'razao_social': 'Empresa Brasileira Ltda',
            'nome_fantasia': 'Fantasia',
            'situacao': 'ATIVA',
          };

          final data = CnpjCompanyData.fromJson(json);

          expect(data.cnpj, equals(validCnpjRaw));
          expect(data.legalName, equals('Empresa Brasileira Ltda'));
          expect(data.tradeName, equals('Fantasia'));
          expect(data.situation, equals('ATIVA'));
          expect(data.isActive, isTrue);
        },
      );

      test('toJson produces a clean map with current state', () {
        final data = CnpjCompanyData(
          cnpj: validCnpjMasked,
          legalName: 'Legal',
          situation: 'ATIVA',
        );

        final json = data.toJson();

        expect(json['cnpj'], equals(validCnpjRaw));
        expect(json['legal_name'], equals('Legal'));
        expect(json['situation'], equals('ATIVA'));
      });
    });

    // ── 3. isActive (Business Logic Integrity) ──────────────────────────────
    group('isActive', () {
      test(
        'returns true for "ATIVA" regardless of case and surrounding spaces',
        () {
          final scenarios = ['ATIVA', 'ativa', '  ATIVA  ', 'Ativa'];
          for (final s in scenarios) {
            final data = CnpjCompanyData(cnpj: validCnpjRaw, situation: s);
            expect(
              data.isActive,
              isTrue,
              reason: 'Should be active for situation: "$s"',
            );
          }
        },
      );

      test('returns false for non-active statuses', () {
        final scenarios = ['BAIXADA', 'INAPTA', 'SUSPENSA', '', null];
        for (final s in scenarios) {
          final data = CnpjCompanyData(cnpj: validCnpjRaw, situation: s);
          expect(data.isActive, isFalse);
        }
      });
    });

    // ── 4. Value Equality (Equatable) ────────────────────────────────────────
    group('value equality', () {
      test('instances with same values are equal (Value Object integrity)', () {
        final a = CnpjCompanyData(
          cnpj: validCnpjMasked,
          legalName: 'Company',
          situation: 'ATIVA',
        );
        final b = CnpjCompanyData(
          cnpj: validCnpjRaw, // different input format
          legalName: 'Company',
          situation: 'ATIVA',
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('instances with different CNPJs are NOT equal', () {
        final a = CnpjCompanyData(cnpj: '11111111000111');
        final b = CnpjCompanyData(cnpj: '22222222000122');
        expect(a, isNot(equals(b)));
      });
    });
  });
}
