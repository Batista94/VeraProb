import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/tenant_status_filter.dart';

void main() {
  group('TenantStatusFilter', () {
    group('all', () {
      test('matches active tenant', () {
        expect(
          TenantStatusFilter.all.matches(isActive: true, isArchived: false),
          isTrue,
        );
      });

      test('matches suspended tenant', () {
        expect(
          TenantStatusFilter.all.matches(isActive: false, isArchived: false),
          isTrue,
        );
      });

      test('matches archived tenant', () {
        expect(
          TenantStatusFilter.all.matches(isActive: false, isArchived: true),
          isTrue,
        );
      });

      test('label is non-empty', () {
        expect(TenantStatusFilter.all.label, isNotEmpty);
      });
    });

    group('active', () {
      test('matches active tenant', () {
        expect(
          TenantStatusFilter.active.matches(isActive: true, isArchived: false),
          isTrue,
        );
      });

      test('does not match suspended tenant', () {
        expect(
          TenantStatusFilter.active.matches(isActive: false, isArchived: false),
          isFalse,
        );
      });

      test('does not match archived tenant', () {
        expect(
          TenantStatusFilter.active.matches(isActive: false, isArchived: true),
          isFalse,
        );
      });

      test('label is non-empty', () {
        expect(TenantStatusFilter.active.label, isNotEmpty);
      });
    });

    group('suspended', () {
      test('does not match active tenant', () {
        expect(
          TenantStatusFilter.suspended.matches(
            isActive: true,
            isArchived: false,
          ),
          isFalse,
        );
      });

      test('matches suspended tenant', () {
        expect(
          TenantStatusFilter.suspended.matches(
            isActive: false,
            isArchived: false,
          ),
          isTrue,
        );
      });

      test('does not match archived tenant', () {
        expect(
          TenantStatusFilter.suspended.matches(
            isActive: false,
            isArchived: true,
          ),
          isFalse,
        );
      });

      test('label is non-empty', () {
        expect(TenantStatusFilter.suspended.label, isNotEmpty);
      });
    });

    group('archived', () {
      test('matches archived tenant', () {
        expect(
          TenantStatusFilter.archived.matches(
            isActive: false,
            isArchived: true,
          ),
          isTrue,
        );
      });

      test('does not match active tenant', () {
        expect(
          TenantStatusFilter.archived.matches(
            isActive: true,
            isArchived: false,
          ),
          isFalse,
        );
      });

      test('does not match suspended tenant', () {
        expect(
          TenantStatusFilter.archived.matches(
            isActive: false,
            isArchived: false,
          ),
          isFalse,
        );
      });

      test('label is non-empty', () {
        expect(TenantStatusFilter.archived.label, isNotEmpty);
      });
    });

    test('all enum values have distinct labels', () {
      final labels = TenantStatusFilter.values.map((f) => f.label).toSet();
      expect(labels.length, equals(TenantStatusFilter.values.length));
    });

    test('each valid tenant state matches exactly one specific filter', () {
      // Valid states: active, suspended, archived.
      final states = [
        (isActive: true, isArchived: false), // active
        (isActive: false, isArchived: false), // suspended
        (isActive: false, isArchived: true), // archived
      ];
      final specific = [
        TenantStatusFilter.active,
        TenantStatusFilter.suspended,
        TenantStatusFilter.archived,
      ];

      for (final state in states) {
        expect(
          TenantStatusFilter.all.matches(
            isActive: state.isActive,
            isArchived: state.isArchived,
          ),
          isTrue,
        );

        final matchCount = specific
            .where(
              (f) => f.matches(
                isActive: state.isActive,
                isArchived: state.isArchived,
              ),
            )
            .length;
        expect(
          matchCount,
          equals(1),
          reason:
              'isActive=${state.isActive}, isArchived=${state.isArchived} must match exactly one specific filter',
        );
      }
    });

    test(
      'no OrgStatus domain import required — filter operates on primitives',
      () {
        expect(
          TenantStatusFilter.active.matches(isActive: true, isArchived: false),
          isA<bool>(),
        );
      },
    );
  });
}
