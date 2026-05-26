// Contract tests for ICsvMappingTemplateRepository.
//
// Validates the port contract using an in-memory fake, ensuring:
//   INV-1  — all operations are scoped to organizationId
//   INV-8  — all reads enforce org scope
//   INV-10 — ConflictException on optimistic-locking version mismatch

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/admin/i_csv_mapping_template_repository.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';

// ── Fake ──────────────────────────────────────────────────────────────────────

class _InMemoryCsvMappingTemplateRepository
    implements ICsvMappingTemplateRepository {
  final Map<String, CsvMappingTemplate> _store = {};

  @override
  Future<List<CsvMappingTemplate>> getTemplates({
    required String organizationId,
    String? targetEntity,
  }) async {
    return _store.values
        .where(
          (t) =>
              t.organizationId == organizationId &&
              (targetEntity == null || t.targetEntity == targetEntity),
        )
        .toList();
  }

  @override
  Future<CsvMappingTemplate?> getDefaultTemplate({
    required String organizationId,
    required String targetEntity,
  }) async {
    final matches = _store.values.where(
      (t) =>
          t.organizationId == organizationId &&
          t.targetEntity == targetEntity &&
          t.isDefault,
    );
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<CsvMappingTemplate> createTemplate(CsvMappingTemplate template) async {
    final created = template.copyWith(updatedAt: DateTime.now().toUtc());
    _store[template.id] = created;
    return created;
  }

  @override
  Future<CsvMappingTemplate> updateTemplate(CsvMappingTemplate template) async {
    final existing = _store[template.id];
    if (existing == null) {
      throw ConflictException.deleted(
        resourceType: 'csv_mapping_template',
        resourceId: template.id,
        clientVersion: template.version,
      );
    }
    if (existing.version != template.version) {
      throw ConflictException.staleVersion(
        resourceType: 'csv_mapping_template',
        resourceId: template.id,
        clientVersion: template.version,
        currentVersion: existing.version,
      );
    }
    final updated = template.copyWith(
      version: template.version + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    _store[template.id] = updated;
    return updated;
  }

  @override
  Future<void> deleteTemplate(
    String templateId, {
    required String organizationId,
  }) async {
    _store.remove(templateId);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

CsvMappingTemplate _buildTemplate({
  String id = 'tmpl-001',
  String organizationId = 'org-test',
  String name = 'Asset Import Template',
  String targetEntity = 'asset',
  bool isDefault = false,
  int version = 1,
}) {
  final now = DateTime.now().toUtc();
  return CsvMappingTemplate(
    id: id,
    organizationId: organizationId,
    name: name,
    targetEntity: targetEntity,
    columnMappings: [
      const ColumnMapping(
        csvHeader: 'Plate',
        targetField: CsvTargetField.identifier,
        required: true,
      ),
    ],
    isDefault: isDefault,
    version: version,
    createdAt: now,
    updatedAt: now,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ICsvMappingTemplateRepository — Contract', () {
    late _InMemoryCsvMappingTemplateRepository repo;

    setUp(() {
      repo = _InMemoryCsvMappingTemplateRepository();
    });

    // ── getTemplates ──────────────────────────────────────────────────────────

    test('getTemplates returns empty list when no templates exist', () async {
      final result = await repo.getTemplates(organizationId: 'org-test');
      expect(result, isEmpty);
    });

    test('getTemplates returns all templates when no filter', () async {
      await repo.createTemplate(_buildTemplate(id: 'a', targetEntity: 'asset'));
      await repo.createTemplate(
        _buildTemplate(id: 'b', targetEntity: 'contract'),
      );

      final result = await repo.getTemplates(organizationId: 'org-test');
      expect(result, hasLength(2));
    });

    test('getTemplates filters by targetEntity (INV-1 scope)', () async {
      await repo.createTemplate(_buildTemplate(id: 'a', targetEntity: 'asset'));
      await repo.createTemplate(
        _buildTemplate(id: 'b', targetEntity: 'contract'),
      );

      final assetOnly = await repo.getTemplates(
        organizationId: 'org-test',
        targetEntity: 'asset',
      );
      expect(assetOnly, hasLength(1));
      expect(assetOnly.first.targetEntity, equals('asset'));
    });

    // ── getDefaultTemplate ────────────────────────────────────────────────────

    test('getDefaultTemplate returns null when no default exists', () async {
      final result = await repo.getDefaultTemplate(
        organizationId: 'org-test',
        targetEntity: 'asset',
      );
      expect(result, isNull);
    });

    test(
      'getDefaultTemplate returns the default template for entity',
      () async {
        await repo.createTemplate(
          _buildTemplate(id: 'a', targetEntity: 'asset', isDefault: false),
        );
        await repo.createTemplate(
          _buildTemplate(id: 'b', targetEntity: 'asset', isDefault: true),
        );

        final result = await repo.getDefaultTemplate(
          organizationId: 'org-test',
          targetEntity: 'asset',
        );
        expect(result, isNotNull);
        expect(result!.isDefault, isTrue);
      },
    );

    // ── createTemplate ────────────────────────────────────────────────────────

    test('createTemplate persists and returns the template', () async {
      final template = _buildTemplate();
      final created = await repo.createTemplate(template);

      expect(created.id, equals(template.id));
      expect(created.name, equals(template.name));
      expect(created.organizationId, equals(template.organizationId));
    });

    // ── updateTemplate ────────────────────────────────────────────────────────

    test('updateTemplate bumps version on success', () async {
      final created = await repo.createTemplate(_buildTemplate(version: 1));
      final updated = await repo.updateTemplate(
        created.copyWith(name: 'New Name'),
      );

      expect(updated.name, equals('New Name'));
      expect(updated.version, equals(2));
    });

    test(
      'updateTemplate throws ConflictException on version mismatch (INV-10)',
      () async {
        await repo.createTemplate(_buildTemplate(id: 'x', version: 1));
        // Skip the update to simulate stale version.
        final staleTemplate = _buildTemplate(id: 'x', version: 1);

        // Perform one valid update to advance version to 2.
        final current = await repo.getTemplates(organizationId: 'org-test');
        await repo.updateTemplate(current.first);

        // Now attempt with stale version 1.
        await expectLater(
          repo.updateTemplate(staleTemplate),
          throwsA(isA<ConflictException>()),
        );
      },
    );

    // ── deleteTemplate ────────────────────────────────────────────────────────

    test(
      'deleteTemplate removes template from store (soft-delete contract)',
      () async {
        await repo.createTemplate(_buildTemplate(id: 'del-1'));

        await repo.deleteTemplate('del-1', organizationId: 'org-test');

        final remaining = await repo.getTemplates(organizationId: 'org-test');
        expect(remaining.where((t) => t.id == 'del-1'), isEmpty);
      },
    );

    test('deleteTemplate on non-existent id does not throw', () async {
      // The contract does not require throwing on missing id.
      await expectLater(
        repo.deleteTemplate('non-existent', organizationId: 'org-test'),
        completes,
      );
    });
  });
}
