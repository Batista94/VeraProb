import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/attestation_header.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

void main() {
  final validUtc = DateTime.utc(2026, 4, 1, 12, 0, 0);

  AttestationHeader createValid({
    String tenantName = 'Prefeitura SP',
    String? tenantCnpj = '00.000.000/0001-91',
    String contractorName = 'Transportes ABC',
    String? contractorCnpj = '11.111.111/0001-55',
    String generatedBy = 'auditor@sp.gov.br',
    DateTime? generatedAt,
    String engineVersion = 'v2.5.0',
  }) {
    return AttestationHeader.create(
      tenantName: tenantName,
      tenantCnpj: tenantCnpj,
      contractorName: contractorName,
      contractorCnpj: contractorCnpj,
      reportGeneratedBy: generatedBy,
      reportGeneratedAtUtc: generatedAt ?? validUtc,
      engineVersion: engineVersion,
    );
  }

  group('AttestationHeader.create — validation (INV-21)', () {
    test('creates valid header with all fields', () {
      final h = createValid();
      expect(h.tenantName, 'Prefeitura SP');
      expect(h.contractorName, 'Transportes ABC');
      expect(h.reportGeneratedAtUtc.isUtc, isTrue);
      expect(h.engineVersion, 'v2.5.0');
      expect(h.platformVersion, 'veraprob 7.1'); // default
    });

    test('allows null CNPJ fields (test/sandbox environments)', () {
      final h = createValid(tenantCnpj: null, contractorCnpj: null);
      expect(h.tenantCnpj, isNull);
      expect(h.contractorCnpj, isNull);
    });

    test('throws DomainException for empty tenantName', () {
      expect(
        () => createValid(tenantName: ''),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => createValid(tenantName: '   '),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty contractorName', () {
      expect(
        () => createValid(contractorName: ''),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => createValid(contractorName: '   '),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty reportGeneratedBy', () {
      expect(
        () => createValid(generatedBy: ''),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => createValid(generatedBy: '   '),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for non-UTC timestamp (INV-9)', () {
      final localTime = DateTime(2026, 4, 1, 12, 0, 0); // local time
      expect(
        () => createValid(generatedAt: localTime),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty engineVersion', () {
      expect(
        () => createValid(engineVersion: ''),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => createValid(engineVersion: '   '),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('AttestationHeader — legal text generation', () {
    test('legalNotice contains platform version', () {
      final h = createValid();
      expect(h.legalNotice, contains('veraprob 7.1'));
      expect(h.legalNotice, contains('CPC Art. 369–376'));
    });

    test('immutabilityStatement mentions append-only and RLS', () {
      final h = createValid();
      expect(h.immutabilityStatement, contains('append-only'));
      expect(h.immutabilityStatement, contains('Row Level Security'));
    });

    test('verificationInstructions contains all passed parameters', () {
      final h = createValid();
      final instructions = h.verificationInstructions(
        organizationId: 'org-abc',
        contractScope: 'contract-xyz',
        periodStart: '2026-03-01',
        periodEnd: '2026-03-31',
      );
      expect(instructions, contains('org-abc'));
      expect(instructions, contains('contract-xyz'));
      expect(instructions, contains('2026-03-01'));
      expect(instructions, contains('2026-03-31'));
      expect(instructions, contains('SHA-256'));
    });
  });

  group('AttestationHeader.reconstitute', () {
    test('reconstitutes without validation — trusts stored values', () {
      final h = AttestationHeader.reconstitute(
        tenantName: 'T',
        tenantCnpj: null,
        contractorName: 'C',
        contractorCnpj: null,
        reportGeneratedBy: 'user',
        reportGeneratedAtUtc: validUtc,
        engineVersion: 'v1.0',
        platformVersion: 'veraprob 6.0',
      );
      expect(h.platformVersion, 'veraprob 6.0');
      expect(h.engineVersion, 'v1.0');
    });
  });

  group('AttestationHeader — equality', () {
    test('two headers with same fields are equal', () {
      final h1 = createValid();
      final h2 = createValid();
      expect(h1, equals(h2));
    });

    test('two headers differ when engineVersion differs', () {
      final h1 = createValid(engineVersion: 'v1.0');
      final h2 = createValid(engineVersion: 'v2.0');
      expect(h1, isNot(equals(h2)));
    });
  });
}
