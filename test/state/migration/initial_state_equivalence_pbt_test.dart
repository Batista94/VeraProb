/// **Validates: Requirements 2.6**
///
/// Property 2: Initial State Equivalence
///
/// For any migrated notifier that previously initialized state via
/// `super(initialState)`, creating a fresh instance via its provider SHALL yield
/// a state equal to the original initial state value (e.g.,
/// `const AsyncData(null)` for action notifiers, `const AuditFilterState()`
/// for filter notifiers).
///
/// Strategy: Since the project is in a partially-migrated state, this test uses
/// a source-file verification approach:
///
/// 1. Defines the expected initial state pattern for each migrated notifier
/// 2. Uses Glados to randomly select notifiers
/// 3. Reads the source file and verifies that the `build()` method returns
///    the expected initial state expression
/// 4. Verifies structural invariants (build() exists, returns correct pattern)
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 2: Initial State Equivalence

/// Represents the expected initial state configuration for a migrated notifier.
class InitialStateSpec {
  /// The notifier class name.
  final String notifierName;

  /// The source file path relative to project root.
  final String sourceFile;

  /// The expected return expression in the `build()` method.
  /// This is the literal string that should appear as the return value.
  final String expectedBuildReturn;

  /// The state type declared in the Notifier generic parameter.
  final String stateType;

  /// Description of what the initial state represents.
  final String description;

  const InitialStateSpec({
    required this.notifierName,
    required this.sourceFile,
    required this.expectedBuildReturn,
    required this.stateType,
    required this.description,
  });

  @override
  String toString() => '$notifierName → $expectedBuildReturn';
}

/// The complete expected initial state specifications for all migrated notifiers.
/// These match the original `super(initialState)` values from the StateNotifier
/// implementations, now expressed as `build()` return values.
const _initialStateSpecs = <InitialStateSpec>[
  // ── Action Notifiers (AsyncValue<void>) ─────────────────────────────────
  InitialStateSpec(
    notifierName: 'SanctionActionNotifier',
    sourceFile: 'lib/state/providers/auditor_queue_providers.dart',
    expectedBuildReturn: 'const AsyncData(null)',
    stateType: 'AsyncValue<void>',
    description:
        'Action notifier starts in idle success state (no operation pending)',
  ),
  InitialStateSpec(
    notifierName: 'JustificationActionNotifier',
    sourceFile: 'lib/state/providers/justification_providers.dart',
    expectedBuildReturn: 'const AsyncData(null)',
    stateType: 'AsyncValue<void>',
    description:
        'Action notifier starts in idle success state (no operation pending)',
  ),

  // ── Telegram Notifiers (AsyncValue<T?>) ─────────────────────────────────
  InitialStateSpec(
    notifierName: 'TelegramBindingNotifier',
    sourceFile: 'lib/state/providers/telegram_providers.dart',
    expectedBuildReturn: 'const AsyncData(null)',
    stateType: 'AsyncValue<TelegramBindingToken?>',
    description: 'Binding notifier starts with no token (nullable data)',
  ),
  InitialStateSpec(
    notifierName: 'LinkEvidenceNotifier',
    sourceFile: 'lib/state/providers/telegram_providers.dart',
    expectedBuildReturn: 'const AsyncData(null)',
    stateType: 'AsyncValue<TelegramEvidenceLink?>',
    description: 'Link notifier starts with no link (nullable data)',
  ),

  // ── Filter Notifiers (domain state) ─────────────────────────────────────
  InitialStateSpec(
    notifierName: 'CommandCenterFilterNotifier',
    sourceFile:
        'lib/application/projections/providers/command_center_filter_provider.dart',
    expectedBuildReturn: 'const CommandCenterFilterState()',
    stateType: 'CommandCenterFilterState',
    description:
        'Filter notifier starts with default filter state (all filters cleared)',
  ),
  InitialStateSpec(
    notifierName: 'AuditFilterNotifier',
    sourceFile:
        'lib/application/projections/providers/audit_filter_provider.dart',
    expectedBuildReturn: 'const AuditFilterState()',
    stateType: 'AuditFilterState',
    description:
        'Filter notifier starts with default filter state (all filters cleared)',
  ),
];

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
  group('Property 2: Initial State Equivalence', () {
    // ── Sub-property: build() method exists and returns expected value ─────
    Glados(
      any.intInRange(0, _initialStateSpecs.length - 1),
    ).test('build() returns the expected initial state expression', (index) {
      final spec = _initialStateSpecs[index];
      final sourceFile = File(spec.sourceFile);

      expect(
        sourceFile.existsSync(),
        isTrue,
        reason: 'Source file ${spec.sourceFile} must exist',
      );

      final content = sourceFile.readAsStringSync();

      // Find the class definition
      final classStart = content.indexOf('class ${spec.notifierName}');
      expect(
        classStart,
        isNot(-1),
        reason:
            '${spec.notifierName} class must be defined in ${spec.sourceFile}',
      );

      // Extract content from class start to find its build() method
      final afterClass = content.substring(classStart);

      // Verify build() method exists
      expect(
        afterClass.contains('build()'),
        isTrue,
        reason:
            '${spec.notifierName} must have a build() method (v3 Notifier requirement)',
      );

      // Verify the expected return expression exists in the build() method
      // We look for the return statement containing the expected initial state
      expect(
        afterClass.contains('return ${spec.expectedBuildReturn}'),
        isTrue,
        reason:
            '${spec.notifierName}.build() must return "${spec.expectedBuildReturn}" '
            'to preserve initial state equivalence with the original '
            'super(initialState) call',
      );
    });

    // ── Sub-property: State type matches Notifier generic parameter ───────
    Glados(any.intInRange(0, _initialStateSpecs.length - 1)).test(
      'notifier declares the correct state type in its generic parameter',
      (index) {
        final spec = _initialStateSpecs[index];
        final sourceFile = File(spec.sourceFile);

        expect(
          sourceFile.existsSync(),
          isTrue,
          reason: 'Source file ${spec.sourceFile} must exist',
        );

        final content = sourceFile.readAsStringSync();

        // Verify the class extends Notifier with the correct state type.
        // Tolerates whitespace inserted by `dart format` when the line wraps
        // past the 80-column limit (e.g. between class name and `extends`).
        final escapedType = RegExp.escape(spec.stateType);
        final pattern = RegExp(
          r'class\s+'
          '${RegExp.escape(spec.notifierName)}'
          r'\s+extends\s+Notifier<'
          '$escapedType'
          r'>',
        );
        expect(
          pattern.hasMatch(content),
          isTrue,
          reason:
              '${spec.notifierName} must extend Notifier<${spec.stateType}> '
              'to preserve the same state type as the original StateNotifier',
        );
      },
    );

    // ── Sub-property: No legacy super(initialState) pattern ───────────────
    Glados(
      any.choose(_allNotifierNames),
    ).test('no notifier uses legacy super(initialState) pattern', (
      notifierName,
    ) {
      final spec = _initialStateSpecs.firstWhere(
        (s) => s.notifierName == notifierName,
      );
      final sourceFile = File(spec.sourceFile);
      final content = sourceFile.readAsStringSync();

      // Find the class body
      final classStart = content.indexOf('class ${spec.notifierName}');
      expect(
        classStart,
        isNot(-1),
        reason: '${spec.notifierName} class must exist',
      );

      final afterClass = content.substring(classStart);

      // Find the next class definition or end of file to scope our search
      final nextClassIndex = afterClass.indexOf(RegExp(r'\nclass '), 1);
      final classBody = nextClassIndex != -1
          ? afterClass.substring(0, nextClassIndex)
          : afterClass;

      // The class should NOT contain super(...) with a state value
      // (legacy StateNotifier pattern)
      expect(
        classBody.contains(RegExp(r'super\s*\(\s*const\s+')),
        isFalse,
        reason:
            '${spec.notifierName} must NOT use legacy super(initialState) pattern. '
            'Initial state should be returned from build() method instead.',
      );
    });

    // ── Sub-property: build() is annotated with @override ─────────────────
    Glados(any.choose(_allNotifierNames)).test(
      'build() method has @override annotation',
      (notifierName) {
        final spec = _initialStateSpecs.firstWhere(
          (s) => s.notifierName == notifierName,
        );
        final sourceFile = File(spec.sourceFile);
        final content = sourceFile.readAsStringSync();

        // Find the class body
        final classStart = content.indexOf('class ${spec.notifierName}');
        final afterClass = content.substring(classStart);

        // Verify @override appears before build()
        final buildIndex = afterClass.indexOf('build()');
        expect(
          buildIndex,
          isNot(-1),
          reason: '${spec.notifierName} must have a build() method',
        );

        // Look backwards from build() for @override
        final beforeBuild = afterClass.substring(0, buildIndex);
        final lastOverride = beforeBuild.lastIndexOf('@override');
        expect(
          lastOverride,
          isNot(-1),
          reason: '${spec.notifierName}.build() must have @override annotation',
        );

        // Ensure no other method definition between @override and build()
        final betweenOverrideAndBuild = beforeBuild.substring(
          lastOverride + '@override'.length,
        );
        // Should only contain whitespace, return type, and possibly a comment
        expect(
          betweenOverrideAndBuild.contains(
            RegExp(r'\b(void|Future|Stream)\s+\w+\s*\('),
          ),
          isFalse,
          reason:
              '@override must directly precede build() without another method '
              'definition in between for ${spec.notifierName}',
        );
      },
    );

    // ── Sub-property: Spec completeness ───────────────────────────────────
    Glados(any.intInRange(0, _initialStateSpecs.length - 1)).test(
      'every initial state spec has valid non-empty fields',
      (index) {
        final spec = _initialStateSpecs[index];

        expect(
          spec.notifierName,
          isNotEmpty,
          reason: 'Notifier name must be non-empty',
        );
        expect(
          spec.sourceFile,
          isNotEmpty,
          reason: 'Source file path must be non-empty',
        );
        expect(
          spec.expectedBuildReturn,
          isNotEmpty,
          reason: 'Expected build return must be non-empty',
        );
        expect(
          spec.stateType,
          isNotEmpty,
          reason: 'State type must be non-empty',
        );
        expect(
          spec.description,
          isNotEmpty,
          reason: 'Description must be non-empty',
        );
        expect(
          _allNotifierNames.contains(spec.notifierName),
          isTrue,
          reason:
              '${spec.notifierName} must be in the list of all notifier names',
        );
      },
    );

    // ── Sub-property: All 6 notifiers are covered ─────────────────────────
    Glados(any.choose(_allNotifierNames)).test(
      'every notifier in the migration list has an initial state spec',
      (notifierName) {
        final hasSpec = _initialStateSpecs.any(
          (spec) => spec.notifierName == notifierName,
        );

        expect(
          hasSpec,
          isTrue,
          reason:
              '$notifierName must have an InitialStateSpec defined to verify '
              'initial state equivalence',
        );
      },
    );
  });
}
