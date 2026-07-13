import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contractor_view.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';

void main() {
  group('ContractorView.fromRow', () {
    final fullRow = <String, Object?>{
      'id': 'ctr-1',
      'organization_id': 'org-tenant-a',
      'name': 'Transportes Alfa',
      'tax_id': '11.222.333/0001-81',
      'primary_email': 'ops@alfa.com',
      'contact_name': 'Maria Silva',
      'created_at': '2026-04-03T15:30:00Z',
    };

    test('happy path — maps all fields and forces UTC (INV-6)', () {
      final view = ContractorView.fromRow(fullRow);

      expect(view.id, 'ctr-1');
      expect(view.organizationId, 'org-tenant-a');
      expect(view.name, 'Transportes Alfa');
      expect(view.taxId, '11.222.333/0001-81');
      expect(view.primaryEmail, 'ops@alfa.com');
      expect(view.contactName, 'Maria Silva');
      expect(view.createdAtUtc.isUtc, isTrue);
      expect(view.createdAtUtc, DateTime.utc(2026, 4, 3, 15, 30));
    });

    test('null tax_id preserved (optional field)', () {
      final row = Map<String, Object?>.from(fullRow)..['tax_id'] = null;
      final view = ContractorView.fromRow(row);
      expect(view.taxId, isNull);
    });

    test(
      'missing organization_id fails fast (INV-22 Confidentiality — no silent default)',
      () {
        final row = Map<String, Object?>.from(fullRow)
          ..remove('organization_id');
        expect(() => ContractorView.fromRow(row), throwsA(isA<TypeError>()));
      },
    );

    test('missing id fails fast (Integrity)', () {
      final row = Map<String, Object?>.from(fullRow)..remove('id');
      expect(() => ContractorView.fromRow(row), throwsA(isA<TypeError>()));
    });

    test(
      'offset timestamp normalized to UTC (adversarial local-time leak)',
      () {
        final row = Map<String, Object?>.from(fullRow)
          ..['created_at'] = '2026-04-03T15:30:00+03:00';
        final view = ContractorView.fromRow(row);
        expect(view.createdAtUtc.isUtc, isTrue);
        expect(view.createdAtUtc, DateTime.utc(2026, 4, 3, 12, 30));
      },
    );
  });

  group('ContractorView.fromDomain', () {
    test('round-trip preserves organization boundary fields', () {
      final domain = Contractor(
        id: 'ctr-2',
        organizationId: 'org-b',
        name: 'Beta Log',
        taxId: null,
        primaryEmail: 'c@beta.com',
        contactName: 'João',
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );
      final view = ContractorView.fromDomain(domain);
      expect(view.organizationId, 'org-b');
      expect(view.taxId, isNull);
      expect(view.createdAtUtc, DateTime.utc(2026, 1, 1));
    });
  });
}
