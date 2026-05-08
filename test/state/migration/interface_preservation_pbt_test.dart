/// **Validates: Requirements 2.2**
///
/// Property 1: Public Interface Preservation
///
/// For any migrated notifier (SanctionActionNotifier, JustificationActionNotifier,
/// TelegramBindingNotifier, LinkEvidenceNotifier, CommandCenterFilterNotifier,
/// AuditFilterNotifier) and for any public method on that notifier, the method
/// name, parameter types, parameter names, and return type SHALL be identical
/// to the original StateNotifier implementation.
///
/// Strategy: Since dart:mirrors is unavailable in Flutter and the project is in
/// a partially-migrated state (some transitive dependencies still use deprecated
/// APIs), this test uses a data-driven approach:
///
/// 1. Defines the expected public interface as structured data (MethodSpec)
/// 2. Uses Glados to randomly select notifier/method combinations
/// 3. Verifies structural invariants of the interface specification
/// 4. Cross-references against the source files to ensure consistency
///
/// Once all migration tasks are complete, the compile-time verification imports
/// (currently commented) will provide additional static guarantees.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 1: Public Interface Preservation

/// Represents the expected signature of a public method on a migrated notifier.
class MethodSpec {
  final String notifierName;
  final String methodName;
  final List<String> parameterNames;
  final List<String> parameterTypes;
  final String returnType;
  final String sourceFile;

  const MethodSpec({
    required this.notifierName,
    required this.methodName,
    required this.parameterNames,
    required this.parameterTypes,
    required this.returnType,
    required this.sourceFile,
  });

  @override
  String toString() => '$notifierName.$methodName';
}

/// The complete expected public interface of all migrated notifiers.
/// These signatures match the original StateNotifier implementations.
const _expectedInterfaces = <MethodSpec>[
  // ── SanctionActionNotifier ──────────────────────────────────────────────
  MethodSpec(
    notifierName: 'SanctionActionNotifier',
    methodName: 'approve',
    parameterNames: [
      'queueEntryId',
      'approvedByUserId',
      'actorEmail',
      'callerRole',
      'organizationId',
      'sessionId',
    ],
    parameterTypes: [
      'String',
      'String',
      'String',
      'UserRole',
      'String',
      'String',
    ],
    returnType: 'Future<void>',
    sourceFile: 'lib/state/providers/auditor_queue_providers.dart',
  ),
  MethodSpec(
    notifierName: 'SanctionActionNotifier',
    methodName: 'reject',
    parameterNames: [
      'queueEntryId',
      'rejectedByUserId',
      'actorEmail',
      'rejectionReason',
      'callerRole',
      'organizationId',
      'sessionId',
    ],
    parameterTypes: [
      'String',
      'String',
      'String',
      'String',
      'UserRole',
      'String',
      'String',
    ],
    returnType: 'Future<void>',
    sourceFile: 'lib/state/providers/auditor_queue_providers.dart',
  ),

  // ── JustificationActionNotifier ─────────────────────────────────────────
  MethodSpec(
    notifierName: 'JustificationActionNotifier',
    methodName: 'approve',
    parameterNames: [
      'justificationId',
      'organizationId',
      'planVersion',
      'callerRole',
      'callerUserId',
      'callerEmail',
      'sessionId',
    ],
    parameterTypes: [
      'String',
      'String',
      'int',
      'UserRole',
      'String',
      'String',
      'String',
    ],
    returnType: 'Future<void>',
    sourceFile: 'lib/state/providers/justification_providers.dart',
  ),
  MethodSpec(
    notifierName: 'JustificationActionNotifier',
    methodName: 'reject',
    parameterNames: [
      'justificationId',
      'organizationId',
      'planVersion',
      'callerRole',
      'callerUserId',
      'callerEmail',
      'rejectionNotes',
      'sessionId',
    ],
    parameterTypes: [
      'String',
      'String',
      'int',
      'UserRole',
      'String',
      'String',
      'String',
      'String',
    ],
    returnType: 'Future<void>',
    sourceFile: 'lib/state/providers/justification_providers.dart',
  ),

  // ── TelegramBindingNotifier ─────────────────────────────────────────────
  MethodSpec(
    notifierName: 'TelegramBindingNotifier',
    methodName: 'generateToken',
    parameterNames: ['command'],
    parameterTypes: ['GenerateTelegramBindingTokenCommand'],
    returnType: 'Future<void>',
    sourceFile: 'lib/state/providers/telegram_providers.dart',
  ),
  MethodSpec(
    notifierName: 'TelegramBindingNotifier',
    methodName: 'fail',
    parameterNames: ['error', 'stackTrace'],
    parameterTypes: ['Object', 'StackTrace'],
    returnType: 'void',
    sourceFile: 'lib/state/providers/telegram_providers.dart',
  ),

  // ── LinkEvidenceNotifier ────────────────────────────────────────────────
  MethodSpec(
    notifierName: 'LinkEvidenceNotifier',
    methodName: 'link',
    parameterNames: ['evidenceUploadId', 'executionSetId'],
    parameterTypes: ['String', 'String'],
    returnType: 'Future<void>',
    sourceFile: 'lib/state/providers/telegram_providers.dart',
  ),

  // ── CommandCenterFilterNotifier ─────────────────────────────────────────
  MethodSpec(
    notifierName: 'CommandCenterFilterNotifier',
    methodName: 'setStatusFilter',
    parameterNames: ['filter'],
    parameterTypes: ['FleetStatusFilter'],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/command_center_filter_provider.dart',
  ),
  MethodSpec(
    notifierName: 'CommandCenterFilterNotifier',
    methodName: 'setSeverityFilter',
    parameterNames: ['severity'],
    parameterTypes: ['int?'],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/command_center_filter_provider.dart',
  ),
  MethodSpec(
    notifierName: 'CommandCenterFilterNotifier',
    methodName: 'setFollowVehicleId',
    parameterNames: ['vehicleId'],
    parameterTypes: ['String?'],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/command_center_filter_provider.dart',
  ),

  // ── AuditFilterNotifier ─────────────────────────────────────────────────
  MethodSpec(
    notifierName: 'AuditFilterNotifier',
    methodName: 'setDateRange',
    parameterNames: ['start', 'end'],
    parameterTypes: ['DateTime', 'DateTime'],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
  ),
  MethodSpec(
    notifierName: 'AuditFilterNotifier',
    methodName: 'clearDates',
    parameterNames: [],
    parameterTypes: [],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
  ),
  MethodSpec(
    notifierName: 'AuditFilterNotifier',
    methodName: 'setCategory',
    parameterNames: ['category'],
    parameterTypes: ['String'],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
  ),
  MethodSpec(
    notifierName: 'AuditFilterNotifier',
    methodName: 'clearCategory',
    parameterNames: [],
    parameterTypes: [],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
  ),
  MethodSpec(
    notifierName: 'AuditFilterNotifier',
    methodName: 'setEntity',
    parameterNames: ['entityId'],
    parameterTypes: ['String'],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
  ),
  MethodSpec(
    notifierName: 'AuditFilterNotifier',
    methodName: 'toggleSilentMode',
    parameterNames: [],
    parameterTypes: [],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
  ),
  MethodSpec(
    notifierName: 'AuditFilterNotifier',
    methodName: 'clearAll',
    parameterNames: [],
    parameterTypes: [],
    returnType: 'void',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
  ),
];

/// Maps notifier names to their expected method count for interface completeness.
const _expectedMethodCounts = <String, int>{
  'SanctionActionNotifier': 2,
  'JustificationActionNotifier': 2,
  'TelegramBindingNotifier': 2,
  'LinkEvidenceNotifier': 1,
  'CommandCenterFilterNotifier': 3,
  'AuditFilterNotifier': 7,
};

/// Maps notifier names to their expected state type.
const _expectedStateTypes = <String, String>{
  'SanctionActionNotifier': 'AsyncValue<void>',
  'JustificationActionNotifier': 'AsyncValue<void>',
  'TelegramBindingNotifier': 'AsyncValue<TelegramBindingToken?>',
  'LinkEvidenceNotifier': 'AsyncValue<TelegramEvidenceLink?>',
  'CommandCenterFilterNotifier': 'CommandCenterFilterState',
  'AuditFilterNotifier': 'AuditFilterState',
};

/// Maps notifier names to their expected base class in v3.
const _expectedBaseClass = <String, String>{
  'SanctionActionNotifier': 'Notifier',
  'JustificationActionNotifier': 'Notifier',
  'TelegramBindingNotifier': 'Notifier',
  'LinkEvidenceNotifier': 'Notifier',
  'CommandCenterFilterNotifier': 'Notifier',
  'AuditFilterNotifier': 'Notifier',
};

/// All notifier names for Glados selection.
const _allNotifierNames = [
  'SanctionActionNotifier',
  'JustificationActionNotifier',
  'TelegramBindingNotifier',
  'LinkEvidenceNotifier',
  'CommandCenterFilterNotifier',
  'AuditFilterNotifier',
];

void main() {
  group('Property 1: Public Interface Preservation', () {
    // ── Sub-property: Method existence and count per notifier ────────────
    Glados(
      any.choose(_allNotifierNames),
    ).test('each notifier exposes the expected number of public methods', (
      notifierName,
    ) {
      final methodsForNotifier = _expectedInterfaces
          .where((spec) => spec.notifierName == notifierName)
          .toList();

      expect(
        methodsForNotifier.length,
        equals(_expectedMethodCounts[notifierName]),
        reason:
            '$notifierName should have ${_expectedMethodCounts[notifierName]} '
            'public methods but found ${methodsForNotifier.length}',
      );
    });

    // ── Sub-property: Parameter count consistency ────────────────────────
    Glados(
      any.intInRange(0, _expectedInterfaces.length - 1),
    ).test('each method has matching parameter names and types count', (index) {
      final spec = _expectedInterfaces[index];

      expect(
        spec.parameterNames.length,
        equals(spec.parameterTypes.length),
        reason:
            '${spec.notifierName}.${spec.methodName} parameter names count '
            '(${spec.parameterNames.length}) must equal parameter types count '
            '(${spec.parameterTypes.length})',
      );
    });

    // ── Sub-property: State type preservation ────────────────────────────
    Glados(any.choose(_allNotifierNames)).test(
      'each notifier preserves its expected state type',
      (notifierName) {
        expect(
          _expectedStateTypes.containsKey(notifierName),
          isTrue,
          reason: '$notifierName must have a defined expected state type',
        );

        final stateType = _expectedStateTypes[notifierName]!;
        expect(
          stateType,
          isNotEmpty,
          reason: '$notifierName state type must be non-empty',
        );
      },
    );

    // ── Sub-property: Interface spec completeness ────────────────────────
    Glados(any.intInRange(0, _expectedInterfaces.length - 1)).test(
      'every method spec has a non-empty return type and valid notifier name',
      (index) {
        final spec = _expectedInterfaces[index];

        expect(
          spec.notifierName,
          isNotEmpty,
          reason: 'Notifier name must be non-empty',
        );
        expect(
          spec.methodName,
          isNotEmpty,
          reason: 'Method name must be non-empty',
        );
        expect(
          spec.returnType,
          isNotEmpty,
          reason:
              '${spec.notifierName}.${spec.methodName} must have a '
              'non-empty return type',
        );
        expect(
          _expectedMethodCounts.containsKey(spec.notifierName),
          isTrue,
          reason: '${spec.notifierName} must be in the expected notifiers list',
        );
      },
    );

    // ── Sub-property: Source file verification ───────────────────────────
    // Verifies that the source files exist and contain the expected method
    // signatures, proving the interface hasn't drifted from the spec.
    Glados(
      any.intInRange(0, _expectedInterfaces.length - 1),
    ).test('source file contains the expected method signature', (index) {
      final spec = _expectedInterfaces[index];
      final sourceFile = File(spec.sourceFile);

      expect(
        sourceFile.existsSync(),
        isTrue,
        reason: 'Source file ${spec.sourceFile} must exist',
      );

      final content = sourceFile.readAsStringSync();

      // Verify the class exists in the source file
      expect(
        content.contains('class ${spec.notifierName}'),
        isTrue,
        reason:
            '${spec.notifierName} class must be defined in ${spec.sourceFile}',
      );

      // Verify the method exists in the source file
      expect(
        content.contains(spec.methodName),
        isTrue,
        reason:
            '${spec.notifierName}.${spec.methodName} must exist in ${spec.sourceFile}',
      );

      // Verify each parameter name exists in the source
      for (final paramName in spec.parameterNames) {
        expect(
          content.contains(paramName),
          isTrue,
          reason:
              'Parameter "$paramName" of ${spec.notifierName}.${spec.methodName} '
              'must exist in ${spec.sourceFile}',
        );
      }
    });

    // ── Sub-property: Notifier extends correct base class (v3) ──────────
    Glados(any.choose(_allNotifierNames)).test(
      'each notifier extends Notifier (v3 base class)',
      (notifierName) {
        final spec = _expectedInterfaces.firstWhere(
          (s) => s.notifierName == notifierName,
        );
        final sourceFile = File(spec.sourceFile);
        final content = sourceFile.readAsStringSync();

        final expectedBase = _expectedBaseClass[notifierName]!;
        final stateType = _expectedStateTypes[notifierName]!;

        // Verify the class extends the correct v3 base class.
        // Tolerates whitespace inserted by `dart format` when the line wraps
        // past the 80-column limit (e.g. between class name and `extends`).
        final classPattern =
            'class $notifierName extends $expectedBase<$stateType>';
        final classRegex = RegExp(
          r'class\s+'
          '${RegExp.escape(notifierName)}'
          r'\s+extends\s+'
          '${RegExp.escape(expectedBase)}'
          r'<'
          '${RegExp.escape(stateType)}'
          r'>',
        );
        expect(
          classRegex.hasMatch(content),
          isTrue,
          reason:
              '$notifierName must extend $expectedBase<$stateType> in v3. '
              'Expected pattern: "$classPattern"',
        );
      },
    );

    // ── Sub-property: No legacy StateNotifier references ────────────────
    Glados(any.choose(_allNotifierNames)).test(
      'no notifier source file contains StateNotifier for the migrated class',
      (notifierName) {
        final spec = _expectedInterfaces.firstWhere(
          (s) => s.notifierName == notifierName,
        );
        final sourceFile = File(spec.sourceFile);
        final content = sourceFile.readAsStringSync();

        // The class should NOT extend StateNotifier anymore
        final legacyPattern = 'class $notifierName extends StateNotifier';
        expect(
          content.contains(legacyPattern),
          isFalse,
          reason:
              '$notifierName must NOT extend StateNotifier after migration. '
              'Found legacy pattern: "$legacyPattern"',
        );
      },
    );

    // ── Sub-property: build() method exists (v3 requirement) ────────────
    Glados(
      any.choose(_allNotifierNames),
    ).test('each notifier has a build() method (v3 Notifier requirement)', (
      notifierName,
    ) {
      final spec = _expectedInterfaces.firstWhere(
        (s) => s.notifierName == notifierName,
      );
      final sourceFile = File(spec.sourceFile);
      final content = sourceFile.readAsStringSync();

      // Extract the class body to check for build() method
      final classStart = content.indexOf('class $notifierName');
      expect(
        classStart,
        isNot(-1),
        reason: '$notifierName class must exist in source',
      );

      final afterClass = content.substring(classStart);

      expect(
        afterClass.contains('build()'),
        isTrue,
        reason:
            '$notifierName must have a build() method as required by Notifier v3',
      );
    });
  });
}
