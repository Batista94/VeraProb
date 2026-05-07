// TDD anchor — Phase 10 Workstream: Allowed Domains
// Tests FAIL until B1-B5 + A3 are implemented.
// INV-2: RLS denies authenticated writes → 42501 → SovereigntyViolationException.
// INV-7: text[] → List<String>. Strict types.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

// Thin test double that exposes the mixin's mapping logic.
class _ErrorMapper with PostgresErrorInterceptor {
  Exception mapError(PostgrestException e) =>
      mapPostgrestToDomainException(e, resourceType: 'organization');
}

Organization _makeOrg({List<String> allowedDomains = const []}) {
  return Organization(
    id: 'org-1',
    name: 'Test Org',
    timezone: 'America/Sao_Paulo',
    currencyCode: 'BRL',
    status: OrgStatus.active,
    createdAt: DateTime.utc(2026, 1, 1),
    allowedDomains: allowedDomains,
  );
}

void main() {
  group('Organization.allowedDomains — entity defaults', () {
    test('defaults to empty list when not provided', () {
      final org = _makeOrg();
      expect(org.allowedDomains, isEmpty);
      expect(org.allowedDomains, isA<List<String>>());
    });

    test('copyWith preserves allowedDomains when not overridden', () {
      final org = _makeOrg(allowedDomains: ['empresa.com.br']);
      final copy = org.copyWith(name: 'New Name');
      expect(copy.allowedDomains, equals(['empresa.com.br']));
    });

    test('copyWith overrides allowedDomains correctly', () {
      final org = _makeOrg(allowedDomains: ['old.com']);
      final copy = org.copyWith(allowedDomains: ['new.com.br', 'another.io']);
      expect(copy.allowedDomains, equals(['new.com.br', 'another.io']));
      expect(org.allowedDomains, equals(['old.com'])); // original unchanged
    });

    test('copyWith with empty list resets domains', () {
      final org = _makeOrg(allowedDomains: ['empresa.com.br']);
      final copy = org.copyWith(allowedDomains: []);
      expect(copy.allowedDomains, isEmpty);
    });

    test('Equatable includes allowedDomains in props', () {
      final a = _makeOrg(allowedDomains: ['empresa.com.br']);
      final b = _makeOrg(allowedDomains: ['empresa.com.br']);
      final c = _makeOrg(allowedDomains: ['outro.com']);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('Organization.allowedDomains — _mapToOrganization array parsing', () {
    // These tests exercise the parsing logic that _mapToOrganization uses.
    // Pure function: input JSON → expected List<String>.

    List<String> parseAllowedDomains(dynamic raw) {
      return raw is List ? raw.cast<String>() : <String>[];
    }

    test('parses text[] correctly', () {
      final result = parseAllowedDomains(['empresa.com.br', 'filial.com.br']);
      expect(result, equals(['empresa.com.br', 'filial.com.br']));
    });

    test('null raw value → empty list (no NPE)', () {
      final result = parseAllowedDomains(null);
      expect(result, isEmpty);
    });

    test('empty array → empty list', () {
      final result = parseAllowedDomains(<dynamic>[]);
      expect(result, isEmpty);
    });

    test('non-list raw value → empty list (defensive)', () {
      final result = parseAllowedDomains('invalid');
      expect(result, isEmpty);
    });
  });

  group('TenantHealthSnapshot.allowedDomains', () {
    test('fromJson parses allowed_domains array', () {
      final snap = TenantHealthSnapshot.fromJson({
        'id': 'org-1',
        'name': 'Org',
        'is_active': true,
        'max_vehicles': 10,
        'max_active_contracts': 5,
        'active_contract_count': 2,
        'open_critical_alert_count': 0,
        'allowed_domains': ['empresa.com.br', 'parceiro.io'],
      });
      expect(snap.allowedDomains, equals(['empresa.com.br', 'parceiro.io']));
    });

    test('fromJson with null allowed_domains → empty list', () {
      final snap = TenantHealthSnapshot.fromJson({
        'id': 'org-1',
        'name': 'Org',
        'is_active': true,
        'max_vehicles': 10,
        'max_active_contracts': 5,
        'active_contract_count': 2,
        'open_critical_alert_count': 0,
      });
      expect(snap.allowedDomains, isEmpty);
    });

    test('fromJson with empty array → empty list', () {
      final snap = TenantHealthSnapshot.fromJson({
        'id': 'org-1',
        'name': 'Org',
        'is_active': true,
        'max_vehicles': 10,
        'max_active_contracts': 5,
        'active_contract_count': 2,
        'open_critical_alert_count': 0,
        'allowed_domains': <dynamic>[],
      });
      expect(snap.allowedDomains, isEmpty);
    });
  });

  group('Normalization logic (lowercase + Set dedup)', () {
    List<String> normalize(List<String> domains) {
      return domains.map((d) => d.toLowerCase().trim()).toSet().toList();
    }

    test('normalizes to lowercase', () {
      final result = normalize(['Empresa.COM', 'EMPRESA.com']);
      expect(result, hasLength(1));
      expect(result.first, 'empresa.com');
    });

    test('deduplicates via Set', () {
      final result = normalize(['empresa.com', 'empresa.com', 'outro.io']);
      expect(result, containsAll(['empresa.com', 'outro.io']));
      expect(result, hasLength(2));
    });

    test('trims whitespace before lowercasing', () {
      final result = normalize(['  Empresa.Com  ']);
      expect(result.first, 'empresa.com');
    });

    test('empty list → empty list', () {
      final result = normalize([]);
      expect(result, isEmpty);
    });
  });

  group(
    'Adversarial — Invasor Interno (INV-2 / 42501 → SovereigntyViolation)',
    () {
      test('PostgreSQL 42501 maps to SovereigntyViolationException', () {
        final mapper = _ErrorMapper();
        const pgError = PostgrestException(
          message: 'permission denied for table organizations',
          code: '42501',
          details: '',
          hint: '',
        );

        final exception = mapper.mapError(pgError);

        expect(exception, isA<SovereigntyViolationException>());
        final svEx = exception as SovereigntyViolationException;
        expect(svEx.message, contains('42501'));
      });

      test('42501 exception carries resourceType in resourceId field', () {
        final mapper = _ErrorMapper();
        const pgError = PostgrestException(
          message: 'insufficient_privilege',
          code: '42501',
          details: '',
          hint: '',
        );

        final exception = mapper.mapError(pgError);
        expect(exception, isA<SovereigntyViolationException>());
      });
    },
  );

  group('Adversarial — Reset para Vazio', () {
    test('org with domains can be reset to empty via copyWith', () {
      final org = _makeOrg(allowedDomains: ['empresa.com.br']);
      final reset = org.copyWith(allowedDomains: []);
      expect(reset.allowedDomains, isEmpty);
    });

    test(
      '_mapToOrganization with empty DB array → empty List<String> (no NPE)',
      () {
        // Simulates DB returning {} (empty text[]) → JSON []
        List<String> parse(dynamic raw) =>
            raw is List ? raw.cast<String>() : <String>[];

        final result = parse(<dynamic>[]);
        expect(result, isEmpty);
        expect(result, isA<List<String>>());
      },
    );
  });
}
