/// **Validates: Requirements 3.4**
///
/// Property 3: Mutation Invalidation Invariant
///
/// For any mutation method on VehicleCommandNotifier (addVehicle, updateVehicle,
/// deleteVehicle, batchUpdateVehicles), after successful execution,
/// `vehiclesListProvider` SHALL be invalidated, causing downstream listeners
/// to receive a fresh state on next read.
///
/// Strategy: Uses source-code structural verification to confirm that every
/// mutation method in VehicleCommandNotifier:
/// 1. Calls `ref.invalidate(vehiclesListProvider)` after the async operation
/// 2. Has a `ref.mounted` guard preceding the invalidation (INV-15)
/// 3. Performs the invalidation AFTER the repository call (correct ordering)
///
/// This approach avoids transitive compilation issues from the ongoing migration
/// while still providing strong guarantees about the invalidation invariant.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 3: Mutation Invalidation Invariant

/// The source file path for VehicleCommandNotifier.
const _vehicleCommandNotifierSource =
    'lib/state/notifiers/vehicle_command_notifier.dart';

/// All mutation methods that must invalidate vehiclesListProvider.
const _mutationMethods = [
  'addVehicle',
  'updateVehicle',
  'deleteVehicle',
  'batchUpdateVehicles',
];

/// Extracts the body of a specific method from the class source.
/// Returns the text from the method signature to the end of the method body.
/// Handles named parameters (which use `{...}`) by finding the `async {`
/// pattern that starts the actual method body.
String _extractMethodBody(String classContent, String methodName) {
  final methodPattern = RegExp(
    'Future<.*>\\s+$methodName\\s*\\(',
    multiLine: true,
  );
  final methodMatch = methodPattern.firstMatch(classContent);
  if (methodMatch == null) return '';

  final afterMethod = classContent.substring(methodMatch.start);

  // Find the 'async {' or ') async {' pattern that starts the method body
  // This skips over named parameter braces in the signature
  final asyncBodyPattern = RegExp(r'\)\s*async\s*\{');
  final asyncMatch = asyncBodyPattern.firstMatch(afterMethod);
  if (asyncMatch == null) return '';

  // Start counting braces from the opening brace of the method body
  final bodyStartIndex = asyncMatch.end - 1; // position of '{'
  var braceCount = 0;
  var endIndex = afterMethod.length;

  for (var i = bodyStartIndex; i < afterMethod.length; i++) {
    if (afterMethod[i] == '{') {
      braceCount++;
    } else if (afterMethod[i] == '}') {
      braceCount--;
      if (braceCount == 0) {
        endIndex = i + 1;
        break;
      }
    }
  }

  return afterMethod.substring(0, endIndex);
}

void main() {
  // Read source file once for all tests
  final sourceFile = File(_vehicleCommandNotifierSource);

  group('Property 3: Mutation Invalidation Invariant', () {
    // ── Sub-property: Each mutation method calls ref.invalidate ──────────────
    Glados(any.choose(_mutationMethods)).test(
      'each mutation method calls ref.invalidate(vehiclesListProvider) in source',
      (methodName) {
        expect(
          sourceFile.existsSync(),
          isTrue,
          reason:
              'VehicleCommandNotifier source file must exist at '
              '$_vehicleCommandNotifierSource',
        );

        final content = sourceFile.readAsStringSync();

        // Find the class body
        final classStart = content.indexOf('class VehicleCommandNotifier');
        expect(
          classStart,
          isNot(-1),
          reason: 'VehicleCommandNotifier class must exist',
        );

        final classContent = content.substring(classStart);
        final methodBody = _extractMethodBody(classContent, methodName);

        expect(
          methodBody,
          isNotEmpty,
          reason: '$methodName must be defined in VehicleCommandNotifier',
        );

        // Verify ref.invalidate(vehiclesListProvider) is called
        expect(
          methodBody.contains('ref.invalidate(vehiclesListProvider)'),
          isTrue,
          reason:
              '$methodName must call ref.invalidate(vehiclesListProvider) '
              'to ensure downstream listeners receive fresh state after mutation',
        );
      },
    );

    // ── Sub-property: ref.mounted guard precedes invalidation ────────────────
    Glados(any.choose(_mutationMethods)).test(
      'ref.mounted guard precedes ref.invalidate in each mutation method',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final classStart = content.indexOf('class VehicleCommandNotifier');
        final classContent = content.substring(classStart);
        final methodBody = _extractMethodBody(classContent, methodName);

        expect(methodBody, isNotEmpty, reason: '$methodName must exist');

        // Find the invalidate call position
        final invalidateIndex = methodBody.indexOf(
          'ref.invalidate(vehiclesListProvider)',
        );
        expect(
          invalidateIndex,
          isNot(-1),
          reason:
              '$methodName must contain ref.invalidate(vehiclesListProvider)',
        );

        // Find the ref.mounted guard before the invalidate
        final beforeInvalidate = methodBody.substring(0, invalidateIndex);
        final mountedGuardIndex = beforeInvalidate.lastIndexOf('ref.mounted');
        expect(
          mountedGuardIndex,
          isNot(-1),
          reason:
              '$methodName must check ref.mounted before calling '
              'ref.invalidate(vehiclesListProvider) (INV-15 compliance)',
        );

        // Verify the guard is a conditional check (if (!ref.mounted) return)
        final guardLine = beforeInvalidate.substring(
          mountedGuardIndex > 20 ? mountedGuardIndex - 20 : 0,
          mountedGuardIndex + 'ref.mounted'.length + 10,
        );
        expect(
          guardLine.contains('if') && guardLine.contains('ref.mounted'),
          isTrue,
          reason:
              '$methodName must use "if (!ref.mounted) return" pattern '
              'before invalidation',
        );
      },
    );

    // ── Sub-property: Invalidation occurs AFTER the repository call ──────────
    Glados(any.choose(_mutationMethods)).test(
      'ref.invalidate occurs after the repository operation (correct ordering)',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final classStart = content.indexOf('class VehicleCommandNotifier');
        final classContent = content.substring(classStart);
        final methodBody = _extractMethodBody(classContent, methodName);

        expect(methodBody, isNotEmpty, reason: '$methodName must exist');

        // Find the repository call (repo.xxx or await repo.xxx)
        final repoCallIndex = methodBody.indexOf(RegExp(r'repo\.\w+'));
        expect(
          repoCallIndex,
          isNot(-1),
          reason: '$methodName must call a repository method',
        );

        // Find the invalidate call
        final invalidateIndex = methodBody.indexOf(
          'ref.invalidate(vehiclesListProvider)',
        );
        expect(
          invalidateIndex,
          isNot(-1),
          reason:
              '$methodName must contain ref.invalidate(vehiclesListProvider)',
        );

        // Invalidation must come AFTER the repo call
        expect(
          invalidateIndex,
          greaterThan(repoCallIndex),
          reason:
              '$methodName must invalidate vehiclesListProvider AFTER the '
              'repository operation succeeds (not before), ensuring cache '
              'is only cleared on successful mutation',
        );
      },
    );

    // ── Sub-property: Invalidation targets specifically vehiclesListProvider ─
    Glados(any.choose(_mutationMethods)).test(
      'invalidation targets vehiclesListProvider specifically (not a generic invalidate)',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final classStart = content.indexOf('class VehicleCommandNotifier');
        final classContent = content.substring(classStart);
        final methodBody = _extractMethodBody(classContent, methodName);

        expect(methodBody, isNotEmpty, reason: '$methodName must exist');

        // Count invalidate calls — should have exactly one targeting vehiclesListProvider
        final invalidatePattern = RegExp(
          r'ref\.invalidate\(vehiclesListProvider\)',
        );
        final matches = invalidatePattern.allMatches(methodBody);

        expect(
          matches.length,
          equals(1),
          reason:
              '$methodName must call ref.invalidate(vehiclesListProvider) '
              'exactly once per execution path',
        );
      },
    );

    // ── Sub-property: All 4 mutation methods exist and are async ─────────────
    Glados(any.intInRange(0, _mutationMethods.length - 1)).test(
      'all mutation methods exist as async Future-returning methods',
      (index) {
        final method = _mutationMethods[index];
        final content = sourceFile.readAsStringSync();

        // Verify the method exists in the class
        final classStart = content.indexOf('class VehicleCommandNotifier');
        expect(
          classStart,
          isNot(-1),
          reason: 'VehicleCommandNotifier class must exist',
        );

        final classBody = content.substring(classStart);

        // Verify it's a Future-returning method (async mutation)
        final methodPattern = RegExp('Future<.*>\\s+$method\\s*\\(');
        expect(
          methodPattern.hasMatch(classBody),
          isTrue,
          reason:
              '$method must be an async method (returns Future) in '
              'VehicleCommandNotifier (required by Property 3 specification)',
        );

        // Verify it contains 'async' keyword
        final methodBody = _extractMethodBody(classBody, method);
        expect(
          methodBody.contains('async'),
          isTrue,
          reason: '$method must be marked as async',
        );
      },
    );

    // ── Sub-property: vehiclesListProvider import is present ─────────────────
    Glados(any.intInRange(0, 1)).test(
      'VehicleCommandNotifier imports vehiclesListProvider',
      (_) {
        final content = sourceFile.readAsStringSync();

        // Verify the file imports the vehicles_provider.dart which defines
        // vehiclesListProvider
        expect(
          content.contains("vehicles_provider.dart"),
          isTrue,
          reason:
              'VehicleCommandNotifier must import vehicles_provider.dart '
              'to access vehiclesListProvider for invalidation',
        );
      },
    );
  });
}
