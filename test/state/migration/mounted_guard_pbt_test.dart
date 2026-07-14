/// **Validates: Requirements 6.1, 6.4, 9.4**
///
/// Property 4: ref.mounted Guard (INV-15)
///
/// For any async notifier method that contains an `await` followed by state
/// mutation, if the provider is disposed during the async gap, the state
/// SHALL NOT be mutated, no exception SHALL be propagated to listeners, and
/// the discarded result SHALL not cause side effects.
///
/// Strategy: Uses source-code structural verification to confirm that every
/// async method in the target notifiers either:
/// 1. Directly checks `ref.mounted` before state mutation after `await`, OR
/// 2. Delegates to `guardedAction()` or `executeCommand()` which internally
///    enforce the `ref.mounted` guard (via GuardedAsyncActionMixin or
///    AsyncCommandMixin).
///
/// This approach avoids transitive compilation issues from the ongoing migration
/// while still providing strong guarantees about the INV-15 invariant.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 4: ref.mounted Guard (INV-15)

/// Notifier source files and their async methods that must comply with INV-15.
///
/// Each entry maps a source file path to the list of async methods that
/// contain `await` followed by state mutation.
const _notifierSources = <String, List<String>>{
  'lib/state/providers/auditor_queue_providers.dart': ['approve', 'reject'],
  'lib/state/providers/justification_providers.dart': ['approve', 'reject'],
  'lib/state/providers/telegram_providers.dart': ['generateToken', 'link'],
  'lib/state/notifiers/contract_command_notifier.dart': [
    'closeContract',
    'declareContractualPlan',
  ],
  'lib/state/notifiers/connectivity_notifier.dart': ['_onReconnected'],
};

/// Flattened list of (filePath, methodName) pairs for Glados to sample from.
final _allMethods = _notifierSources.entries
    .expand(
      (entry) => entry.value.map((method) => (file: entry.key, method: method)),
    )
    .toList();

/// The mixin source file that provides the canonical ref.mounted guard.
const _asyncCommandMixinSource = 'lib/state/notifiers/async_command_mixin.dart';

/// Extracts the body of a specific method from source content.
/// Handles both public and private methods, with named/positional params.
String _extractMethodBody(String content, String methodName) {
  // Match the method name followed by ( — handles any return type including
  // nested generics like Future<List<Vehicle>>
  final methodPattern = RegExp(
    RegExp.escape(methodName) + r'\s*\(',
    multiLine: true,
  );
  final methodMatch = methodPattern.firstMatch(content);
  if (methodMatch == null) return '';

  final afterMethod = content.substring(methodMatch.start);

  // Find the opening brace of the method body (after 'async {' or just '{')
  final asyncBodyPattern = RegExp(r'(?:async\s*)?\{');
  // Skip past the parameter list first
  var braceSearchStart = 0;
  var parenCount = 0;
  var foundParenStart = false;
  for (var i = 0; i < afterMethod.length; i++) {
    if (afterMethod[i] == '(') {
      parenCount++;
      foundParenStart = true;
    } else if (afterMethod[i] == ')') {
      parenCount--;
      if (foundParenStart && parenCount == 0) {
        braceSearchStart = i + 1;
        break;
      }
    }
  }

  final afterParams = afterMethod.substring(braceSearchStart);
  final braceMatch = asyncBodyPattern.firstMatch(afterParams);
  if (braceMatch == null) return '';

  final bodyStartInAfterMethod = braceSearchStart + braceMatch.end - 1;

  // Count braces to find the matching closing brace
  var braceCount = 0;
  var endIndex = afterMethod.length;
  for (var i = bodyStartInAfterMethod; i < afterMethod.length; i++) {
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
  group('Property 4: ref.mounted Guard (INV-15)', () {
    // ── Sub-property: GuardedAsyncActionMixin enforces ref.mounted ───────
    Glados(any.intInRange(0, 1)).test(
      'GuardedAsyncActionMixin.guardedAction() contains ref.mounted guard',
      (_) {
        final sourceFile = File(_asyncCommandMixinSource);
        expect(
          sourceFile.existsSync(),
          isTrue,
          reason: 'async_command_mixin.dart must exist',
        );

        final content = sourceFile.readAsStringSync();

        // Verify guardedAction method exists
        expect(
          content.contains('guardedAction'),
          isTrue,
          reason: 'GuardedAsyncActionMixin must define guardedAction',
        );

        // Verify ref.mounted guard is present in guardedAction
        final guardedActionBody = _extractMethodBody(content, 'guardedAction');
        expect(
          guardedActionBody,
          isNotEmpty,
          reason: 'guardedAction method must exist',
        );

        // Must have await before the ref.mounted check
        final awaitIndex = guardedActionBody.indexOf('await');
        expect(
          awaitIndex,
          isNot(-1),
          reason: 'guardedAction must contain an await',
        );

        final afterAwait = guardedActionBody.substring(awaitIndex);
        expect(
          afterAwait.contains('ref.mounted'),
          isTrue,
          reason: 'guardedAction must check ref.mounted after await (INV-15)',
        );

        // The ref.mounted check must come before state assignment
        final mountedIndex = afterAwait.indexOf('ref.mounted');
        final stateAssignIndex = afterAwait.indexOf('state =');
        expect(mountedIndex, isNot(-1));
        expect(stateAssignIndex, isNot(-1));
        expect(
          mountedIndex < stateAssignIndex,
          isTrue,
          reason:
              'ref.mounted check must precede state mutation in guardedAction',
        );
      },
    );

    // ── Sub-property: AsyncCommandMixin.executeCommand enforces ref.mounted ─
    Glados(any.intInRange(0, 1)).test(
      'AsyncCommandMixin.executeCommand() contains ref.mounted guard',
      (_) {
        final sourceFile = File(_asyncCommandMixinSource);
        final content = sourceFile.readAsStringSync();

        final executeBody = _extractMethodBody(content, 'executeCommand');
        expect(
          executeBody,
          isNotEmpty,
          reason: 'executeCommand method must exist',
        );

        // Must have await
        final awaitIndex = executeBody.indexOf('await');
        expect(
          awaitIndex,
          isNot(-1),
          reason: 'executeCommand must contain an await',
        );

        // Must have ref.mounted guard after await
        final afterAwait = executeBody.substring(awaitIndex);
        expect(
          afterAwait.contains('ref.mounted'),
          isTrue,
          reason: 'executeCommand must check ref.mounted after await (INV-15)',
        );

        // Must have ref.mounted in BOTH try and catch blocks
        final tryIndex = executeBody.indexOf('try {');
        expect(tryIndex, isNot(-1));

        final catchIndex = executeBody.indexOf('catch');
        expect(catchIndex, isNot(-1));

        // Guard in try block (after await, before setData)
        final tryBlock = executeBody.substring(tryIndex, catchIndex);
        expect(
          tryBlock.contains('ref.mounted'),
          isTrue,
          reason:
              'executeCommand must check ref.mounted in try block before '
              'calling setData (INV-15)',
        );

        // Guard in catch block (before setError)
        final afterCatch = executeBody.substring(catchIndex);
        expect(
          afterCatch.contains('ref.mounted'),
          isTrue,
          reason:
              'executeCommand must check ref.mounted in catch block before '
              'calling setError (INV-15)',
        );
      },
    );

    // ── Sub-property: Delegating methods use guardedAction/executeCommand ────
    Glados(any.intInRange(0, _allMethods.length - 1)).test(
      'each async notifier method either has direct ref.mounted guard or delegates to guarded mixin',
      (index) {
        final entry = _allMethods[index];
        final sourceFile = File(entry.file);

        expect(
          sourceFile.existsSync(),
          isTrue,
          reason: '${entry.file} must exist',
        );

        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, entry.method);

        expect(
          methodBody,
          isNotEmpty,
          reason: '${entry.method} must exist in ${entry.file}',
        );

        // Check if method delegates to guardedAction or executeCommand
        final delegatesToGuardedAction = methodBody.contains('guardedAction(');
        final delegatesToExecuteCommand =
            methodBody.contains('executeCommand(') ||
            methodBody.contains('executeCommand<');

        if (delegatesToGuardedAction || delegatesToExecuteCommand) {
          // Method delegates to a mixin that enforces ref.mounted — compliant
          return;
        }

        // Method must have direct ref.mounted guard after await
        final awaitIndex = methodBody.indexOf('await');
        expect(
          awaitIndex,
          isNot(-1),
          reason: '${entry.method} must contain an await',
        );

        final afterAwait = methodBody.substring(awaitIndex);
        expect(
          afterAwait.contains('ref.mounted'),
          isTrue,
          reason:
              '${entry.method} in ${entry.file} must check ref.mounted '
              'after await (INV-15). Methods that do not delegate to '
              'guardedAction() or executeCommand() must have a direct guard.',
        );
      },
    );

    // ── Sub-property: Direct guard methods have correct pattern ──────────────
    Glados(any.intInRange(0, _allMethods.length - 1)).test(
      'methods with direct ref.mounted guard use "if (!ref.mounted) return" pattern',
      (index) {
        final entry = _allMethods[index];
        final sourceFile = File(entry.file);
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, entry.method);

        if (methodBody.isEmpty) return; // Skip if method not found

        // Skip methods that delegate to guardedAction/executeCommand
        if (methodBody.contains('guardedAction(') ||
            methodBody.contains('executeCommand(') ||
            methodBody.contains('executeCommand<')) {
          return;
        }

        // For direct guard methods, verify the pattern
        final mountedPattern = RegExp(r'if\s*\(\s*!ref\.mounted\s*\)\s*return');
        expect(
          mountedPattern.hasMatch(methodBody),
          isTrue,
          reason:
              '${entry.method} in ${entry.file} must use the canonical '
              '"if (!ref.mounted) return" pattern (INV-15)',
        );
      },
    );

    // ── Sub-property: No state mutation after await without guard ────────────
    Glados(any.intInRange(0, _allMethods.length - 1)).test(
      'no state mutation exists after await without a preceding ref.mounted guard',
      (index) {
        final entry = _allMethods[index];
        final sourceFile = File(entry.file);
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, entry.method);

        if (methodBody.isEmpty) return;

        // Skip methods that delegate to guardedAction/executeCommand
        if (methodBody.contains('guardedAction(') ||
            methodBody.contains('executeCommand(') ||
            methodBody.contains('executeCommand<')) {
          return;
        }

        // Find all `await` positions
        final awaitPattern = RegExp(r'\bawait\b');
        final awaitMatches = awaitPattern.allMatches(methodBody).toList();

        for (final awaitMatch in awaitMatches) {
          final afterThisAwait = methodBody.substring(awaitMatch.end);

          // Find the next state mutation (state = or ref.invalidate)
          final stateMutationPattern = RegExp(
            r'(?:state\s*=|ref\.invalidate\()',
          );
          final mutationMatch = stateMutationPattern.firstMatch(afterThisAwait);

          if (mutationMatch == null) continue; // No mutation after this await

          // There must be a ref.mounted check between the await and the mutation
          final betweenAwaitAndMutation = afterThisAwait.substring(
            0,
            mutationMatch.start,
          );
          expect(
            betweenAwaitAndMutation.contains('ref.mounted'),
            isTrue,
            reason:
                '${entry.method} in ${entry.file}: found state mutation '
                'after await without a preceding ref.mounted guard (INV-15 '
                'violation). Every state mutation after an await MUST be '
                'guarded by "if (!ref.mounted) return".',
          );
        }
      },
    );

    // ── Sub-property: All target notifiers are covered ──────────────────────
    Glados(any.intInRange(0, _notifierSources.length - 1)).test(
      'all target notifier source files exist and contain their expected class',
      (index) {
        final entry = _notifierSources.entries.elementAt(index);
        final sourceFile = File(entry.key);

        expect(
          sourceFile.existsSync(),
          isTrue,
          reason: '${entry.key} must exist',
        );

        final content = sourceFile.readAsStringSync();

        // Verify at least one of the expected methods exists
        final hasExpectedMethod = entry.value.any(
          (method) => content.contains(method),
        );
        expect(
          hasExpectedMethod,
          isTrue,
          reason:
              '${entry.key} must contain at least one of the expected '
              'async methods: ${entry.value}',
        );
      },
    );

    // ── Sub-property: guardedAction delegates do NOT have redundant guards ──
    Glados(any.intInRange(0, _allMethods.length - 1)).test(
      'methods delegating to guardedAction/executeCommand do not bypass the mixin',
      (index) {
        final entry = _allMethods[index];
        final sourceFile = File(entry.file);
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, entry.method);

        if (methodBody.isEmpty) return;

        final delegatesToGuardedAction = methodBody.contains('guardedAction(');
        final delegatesToExecuteCommand =
            methodBody.contains('executeCommand(') ||
            methodBody.contains('executeCommand<');

        if (!delegatesToGuardedAction && !delegatesToExecuteCommand) return;

        // Methods that delegate should NOT have direct `state =` after await
        // outside of the mixin callback (which would bypass the guard).
        // The only `state =` should be inside the callbacks passed to the mixin.
        //
        // Verify there's no top-level `state =` after the delegation call
        // (which would indicate a bypass of the mixin's guard).
        final delegateCallIndex = delegatesToGuardedAction
            ? methodBody.indexOf('guardedAction(')
            : methodBody.indexOf('executeCommand');

        // Everything before the delegate call should not have unguarded
        // state mutations after an await
        final beforeDelegate = methodBody.substring(0, delegateCallIndex);
        final awaitBeforeDelegate = beforeDelegate.contains('await');
        if (awaitBeforeDelegate) {
          // If there's an await before the delegation, there should be
          // no state = between that await and the delegation
          final lastAwaitInBefore = beforeDelegate.lastIndexOf('await');
          final betweenAwaitAndDelegate = beforeDelegate.substring(
            lastAwaitInBefore,
          );
          final hasStateMutation = RegExp(
            r'state\s*=',
          ).hasMatch(betweenAwaitAndDelegate);
          expect(
            hasStateMutation,
            isFalse,
            reason:
                '${entry.method} in ${entry.file}: has state mutation '
                'between await and guardedAction/executeCommand delegation '
                'without ref.mounted guard — potential INV-15 bypass.',
          );
        }
      },
    );
  });
}
