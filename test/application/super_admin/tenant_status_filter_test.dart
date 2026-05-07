import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/application/tenant_status_filter.dart';

// Regras de Escrita:
// 1. Use DateTime.now().toUtc() em mocks (mesma linha).
// 2. Use int para valores monetários e taxas (BPS).
// 3. Proibido importar lib/infrastructure em testes de application.

void main() {
  group('TenantStatusFilter', () {
    group('all', () {
      test('matches active tenant', () {
        expect(TenantStatusFilter.all.matches(isActive: true), isTrue);
      });

      test('matches inactive tenant', () {
        expect(TenantStatusFilter.all.matches(isActive: false), isTrue);
      });

      test('label is non-empty', () {
        expect(TenantStatusFilter.all.label, isNotEmpty);
      });
    });

    group('active', () {
      test('matches active tenant', () {
        expect(TenantStatusFilter.active.matches(isActive: true), isTrue);
      });

      test('does not match inactive tenant', () {
        expect(TenantStatusFilter.active.matches(isActive: false), isFalse);
      });

      test('label is non-empty', () {
        expect(TenantStatusFilter.active.label, isNotEmpty);
      });
    });

    group('suspended', () {
      test('does not match active tenant', () {
        expect(TenantStatusFilter.suspended.matches(isActive: true), isFalse);
      });

      test('matches inactive tenant', () {
        expect(TenantStatusFilter.suspended.matches(isActive: false), isTrue);
      });

      test('label is non-empty', () {
        expect(TenantStatusFilter.suspended.label, isNotEmpty);
      });
    });

    test('all enum values have distinct labels', () {
      final labels = TenantStatusFilter.values.map((f) => f.label).toSet();
      expect(labels.length, equals(TenantStatusFilter.values.length));
    });

    test('covers all status scenarios — active + suspended = all', () {
      // A tenant must match exactly one of (active, suspended) and always all.
      for (final isActive in [true, false]) {
        expect(TenantStatusFilter.all.matches(isActive: isActive), isTrue);

        final matchesActive = TenantStatusFilter.active.matches(
          isActive: isActive,
        );
        final matchesSuspended = TenantStatusFilter.suspended.matches(
          isActive: isActive,
        );

        // Exactly one of active/suspended should match for any given state.
        expect(
          matchesActive ^ matchesSuspended,
          isTrue,
          reason:
              'isActive=$isActive should match exactly one of active/suspended',
        );
      }
    });

    test(
      'no OrgStatus domain import required — filter operates on primitives',
      () {
        // Evidence: the test only imports TenantStatusFilter. The matches()
        // signature takes a plain bool, not OrgStatus.
        expect(TenantStatusFilter.active.matches(isActive: true), isA<bool>());
      },
    );
  });
}
