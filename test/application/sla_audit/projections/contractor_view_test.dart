import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contractor_view.dart';

void main() {
  group('ContractorView', () {
    test('can be constructed with required fields', () {
      final now = DateTime.utc(2026, 1, 1);
      final view = ContractorView(
        id: 'c-1',
        organizationId: 'org-1',
        name: 'Transportadora ABC',
        primaryEmail: 'contato@abc.com.br',
        contactName: 'João Silva',
        createdAtUtc: now,
      );
      expect(view.id, 'c-1');
      expect(view.name, 'Transportadora ABC');
      expect(view.taxId, isNull);
    });

    test('taxId is optional', () {
      final view = ContractorView(
        id: 'c-2',
        organizationId: 'org-1',
        name: 'Empresa XYZ',
        primaryEmail: 'xyz@empresa.com',
        contactName: 'Maria Costa',
        createdAtUtc: DateTime.utc(2026, 2, 1),
        taxId: '12.345.678/0001-90',
      );
      expect(view.taxId, '12.345.678/0001-90');
    });

    test('fromDomain factory preserves all fields', () {
      final contractor = _buildDomainContractor();
      final view = ContractorView.fromDomain(contractor);
      expect(view.id, contractor.id);
      expect(view.name, contractor.name);
      expect(view.primaryEmail, contractor.primaryEmail);
    });
  });
}

// Minimal stub to avoid domain import in test
dynamic _buildDomainContractor() => throw UnimplementedError(
  'Replace with real domain object after implementation',
);
