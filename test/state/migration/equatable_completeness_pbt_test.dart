/// **Validates: Requirements 8.3**
///
/// Property 10: Equatable Completeness
///
/// For any domain entity used as provider state (SanctionQueueItemView,
/// OperationalAlert, TelegramBindingToken, TelegramEvidenceLink,
/// CommandCenterFilterState, AuditFilterState, ContractCommandState),
/// two instances with identical semantically-relevant field values SHALL
/// satisfy `==`, and two instances differing in any semantically-relevant
/// field SHALL NOT satisfy `==`.
///
/// Strategy: Source-code structural verification.
///
/// 1. Reads each entity's source file.
/// 2. Extracts all declared instance fields (`final` declarations).
/// 3. Extracts the `props` list (Equatable) or `operator ==` body (manual).
/// 4. Verifies that every semantically-relevant field is included in the
///    equality implementation.
/// 5. Uses Glados to randomly select entity/field combinations and verify
///    structural completeness.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 10: Equatable Completeness

/// Describes a domain entity and its expected equality configuration.
class EntitySpec {
  final String name;
  final String sourceFile;

  /// Fields that are semantically relevant and MUST be in props/==.
  final List<String> semanticFields;

  /// Fields intentionally excluded from equality (documented design decision).
  final List<String> excludedFields;

  /// Whether the entity uses Equatable (true) or manual operator== (false).
  final bool usesEquatable;

  const EntitySpec({
    required this.name,
    required this.sourceFile,
    required this.semanticFields,
    this.excludedFields = const [],
    this.usesEquatable = true,
  });

  @override
  String toString() => name;
}

/// All domain entities used as provider state that must have complete equality.
const _entitySpecs = <EntitySpec>[
  EntitySpec(
    name: 'SanctionQueueItemView',
    sourceFile:
        'lib/application/sla_audit/projections/sanction_queue_item_view.dart',
    semanticFields: [
      'id',
      'organizationId',
      'ledgerEntryId',
      'setId',
      'contractId',
      'verdictEvidence',
      'status',
      'createdAtUtc',
      'reviewedAtUtc',
      'reviewedByUserId',
      'rejectionReason',
      'vehiclePlate',
      'operatorName',
      'firstReviewerId',
      'peerReviewProposedAction',
      'peerReviewExpiresAtUtc',
    ],
    // UI-enriched fields resolved asynchronously — not DB identity.
    excludedFields: ['contractName', 'windowStartUtc', 'windowEndUtc'],
  ),
  EntitySpec(
    name: 'OperationalAlert',
    sourceFile: 'lib/domain/sla_audit/operational_alert.dart',
    semanticFields: [
      'id',
      'organizationId',
      'entityId',
      'contractId',
      'alertType',
      'severity',
      'triggeredAtUtc',
      'triggeringEventId',
      'traceId',
      'context',
      'status',
      'acknowledgedAtUtc',
      'acknowledgedByUserId',
      'resolvedAtUtc',
      'viewedByUserIds',
    ],
  ),
  EntitySpec(
    name: 'TelegramBindingToken',
    sourceFile: 'lib/domain/sla_audit/telegram/telegram_binding_token.dart',
    semanticFields: [
      'id',
      'organizationId',
      'driverId',
      'createdByUserId',
      'code',
      'expiresAtUtc',
      'usedAtUtc',
      'createdAtUtc',
    ],
  ),
  EntitySpec(
    name: 'TelegramEvidenceLink',
    sourceFile: 'lib/domain/sla_audit/telegram/telegram_evidence_link.dart',
    semanticFields: [
      'id',
      'organizationId',
      'evidenceUploadId',
      'executionSetId',
      'linkedAtUtc',
      'linkedByUserId',
      'source',
    ],
  ),
  EntitySpec(
    name: 'CommandCenterFilterState',
    sourceFile:
        'lib/application/projections/providers/command_center_filter_provider.dart',
    semanticFields: [
      'selectedFleetStatusFilter',
      'selectedSeverityFilter',
      'followVehicleId',
    ],
  ),
  EntitySpec(
    name: 'AuditFilterState',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
    semanticFields: [
      'startDate',
      'endDate',
      'eventType',
      'category',
      'entityId',
      'silentMode',
    ],
  ),
  EntitySpec(
    name: 'ContractCommandState',
    sourceFile: 'lib/state/notifiers/contract_command_state.dart',
    semanticFields: ['idempotencyKey', 'status'],
    usesEquatable: false,
  ),
];

/// All entity names for Glados selection.
final _allEntityNames = _entitySpecs.map((e) => e.name).toList();

/// Extracts the `props` getter body from source content for an Equatable class.
/// Returns the list of field names referenced in the props list.
List<String> _extractPropsFields(String content, String className) {
  // Find the props getter
  final propsPattern = RegExp(
    r'List<Object\?>\s+get\s+props\s*=>\s*\[(.*?)\];',
    dotAll: true,
  );
  final match = propsPattern.firstMatch(content);
  if (match == null) return [];

  final propsBody = match.group(1)!;
  // Extract field references (identifiers) from the props list
  final fieldPattern = RegExp(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\b');
  return fieldPattern
      .allMatches(propsBody)
      .map((m) => m.group(1)!)
      .where((name) => !const ['const', 'true', 'false', 'null'].contains(name))
      .toList();
}

/// Extracts field names from the `operator ==` body for manual equality.
/// Returns the list of field names compared in the == operator.
/// Excludes `runtimeType` which is a standard equality boilerplate check.
List<String> _extractOperatorEqFields(String content, String className) {
  // Find the operator == body
  final eqPattern = RegExp(
    r'bool\s+operator\s*==\s*\(Object\s+other\)\s*=>(.*?);',
    dotAll: true,
  );
  final match = eqPattern.firstMatch(content);
  if (match == null) return [];

  final eqBody = match.group(1)!;
  // Extract field comparisons like `idempotencyKey == other.idempotencyKey`
  final fieldPattern = RegExp(r'(\w+)\s*==\s*other\.\1');
  return fieldPattern
      .allMatches(eqBody)
      .map((m) => m.group(1)!)
      .where(
        (name) => name != 'runtimeType',
      ) // Standard boilerplate, not a field
      .toList();
}

/// Extracts all `final` instance field names from a class body.
List<String> _extractInstanceFields(String content, String className) {
  // Find the class body start
  final classStart = content.indexOf('class $className');
  if (classStart == -1) return [];

  final afterClass = content.substring(classStart);

  // Find the opening brace of the class
  final braceStart = afterClass.indexOf('{');
  if (braceStart == -1) return [];

  // Extract final field declarations
  final fieldPattern = RegExp(r'^\s*final\s+\S+\s+(\w+)\s*;', multiLine: true);
  final fields = <String>[];

  for (final match in fieldPattern.allMatches(afterClass)) {
    fields.add(match.group(1)!);
  }

  return fields;
}

void main() {
  group('Property 10: Equatable Completeness', () {
    // ── Sub-property: Source file existence ──────────────────────────────
    Glados(any.choose(_allEntityNames)).test('each entity source file exists', (
      entityName,
    ) {
      final spec = _entitySpecs.firstWhere((s) => s.name == entityName);
      final sourceFile = File(spec.sourceFile);

      expect(
        sourceFile.existsSync(),
        isTrue,
        reason: 'Source file ${spec.sourceFile} for $entityName must exist',
      );
    });

    // ── Sub-property: Entity extends Equatable or has manual == ─────────
    Glados(any.choose(_allEntityNames)).test(
      'each entity implements equality (Equatable or manual operator==)',
      (entityName) {
        final spec = _entitySpecs.firstWhere((s) => s.name == entityName);
        final content = File(spec.sourceFile).readAsStringSync();

        if (spec.usesEquatable) {
          expect(
            content.contains('class ${spec.name} extends Equatable'),
            isTrue,
            reason: '${spec.name} must extend Equatable',
          );
          expect(
            content.contains('get props'),
            isTrue,
            reason: '${spec.name} must override props getter',
          );
        } else {
          expect(
            content.contains('operator =='),
            isTrue,
            reason: '${spec.name} must have manual operator== override',
          );
          expect(
            content.contains('get hashCode'),
            isTrue,
            reason: '${spec.name} must override hashCode',
          );
        }
      },
    );

    // ── Sub-property: All semantic fields are in props/== ───────────────
    Glados(any.choose(_allEntityNames)).test(
      'all semantically-relevant fields are included in equality check',
      (entityName) {
        final spec = _entitySpecs.firstWhere((s) => s.name == entityName);
        final content = File(spec.sourceFile).readAsStringSync();

        final List<String> equalityFields;
        if (spec.usesEquatable) {
          equalityFields = _extractPropsFields(content, spec.name);
        } else {
          equalityFields = _extractOperatorEqFields(content, spec.name);
        }

        for (final field in spec.semanticFields) {
          expect(
            equalityFields.contains(field),
            isTrue,
            reason:
                '${spec.name}: semantic field "$field" must be included in '
                '${spec.usesEquatable ? "props" : "operator=="} for correct '
                'equality. Found fields: $equalityFields',
          );
        }
      },
    );

    // ── Sub-property: Excluded fields are NOT in props ──────────────────
    Glados(any.choose(_allEntityNames)).test(
      'intentionally excluded fields are NOT in equality check',
      (entityName) {
        final spec = _entitySpecs.firstWhere((s) => s.name == entityName);
        if (spec.excludedFields.isEmpty) return;

        final content = File(spec.sourceFile).readAsStringSync();

        final List<String> equalityFields;
        if (spec.usesEquatable) {
          equalityFields = _extractPropsFields(content, spec.name);
        } else {
          equalityFields = _extractOperatorEqFields(content, spec.name);
        }

        for (final field in spec.excludedFields) {
          expect(
            equalityFields.contains(field),
            isFalse,
            reason:
                '${spec.name}: excluded field "$field" must NOT be in '
                '${spec.usesEquatable ? "props" : "operator=="}. '
                'It is intentionally excluded per design documentation.',
          );
        }
      },
    );

    // ── Sub-property: Instance fields coverage completeness ─────────────
    Glados(any.choose(_allEntityNames)).test(
      'every instance field is either in semantic or excluded list',
      (entityName) {
        final spec = _entitySpecs.firstWhere((s) => s.name == entityName);
        final content = File(spec.sourceFile).readAsStringSync();

        final instanceFields = _extractInstanceFields(content, spec.name);
        final allAccountedFields = [
          ...spec.semanticFields,
          ...spec.excludedFields,
        ];

        for (final field in instanceFields) {
          expect(
            allAccountedFields.contains(field),
            isTrue,
            reason:
                '${spec.name}: instance field "$field" is not accounted for. '
                'It must be either in semanticFields (included in equality) '
                'or excludedFields (documented exclusion). '
                'All instance fields: $instanceFields',
          );
        }
      },
    );

    // ── Sub-property: Semantic field count matches props count ───────────
    Glados(any.choose(_allEntityNames)).test(
      'props/== field count matches expected semantic field count',
      (entityName) {
        final spec = _entitySpecs.firstWhere((s) => s.name == entityName);
        final content = File(spec.sourceFile).readAsStringSync();

        final List<String> equalityFields;
        if (spec.usesEquatable) {
          equalityFields = _extractPropsFields(content, spec.name);
        } else {
          equalityFields = _extractOperatorEqFields(content, spec.name);
        }

        // Deduplicate (in case a field appears multiple times in extraction)
        final uniqueEqualityFields = equalityFields.toSet();

        expect(
          uniqueEqualityFields.length,
          equals(spec.semanticFields.length),
          reason:
              '${spec.name}: equality implementation has '
              '${uniqueEqualityFields.length} unique fields but expected '
              '${spec.semanticFields.length} semantic fields. '
              'Found: $uniqueEqualityFields, '
              'Expected: ${spec.semanticFields}',
        );
      },
    );

    // ── Sub-property: No duplicate fields in props ──────────────────────
    Glados(any.choose(_allEntityNames)).test(
      'no duplicate fields in equality implementation',
      (entityName) {
        final spec = _entitySpecs.firstWhere((s) => s.name == entityName);
        final content = File(spec.sourceFile).readAsStringSync();

        if (!spec.usesEquatable) return; // Only relevant for Equatable props

        final equalityFields = _extractPropsFields(content, spec.name);
        final seen = <String>{};
        final duplicates = <String>[];

        for (final field in equalityFields) {
          if (!seen.add(field)) {
            duplicates.add(field);
          }
        }

        expect(
          duplicates,
          isEmpty,
          reason:
              '${spec.name}: props list contains duplicate fields: $duplicates',
        );
      },
    );
  });
}
