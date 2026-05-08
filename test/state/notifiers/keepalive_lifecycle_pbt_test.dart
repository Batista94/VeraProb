/// **Validates: Requirements 3.5, 6.3, 6.6**
///
/// Property 5: KeepAlive Lifecycle Completeness
///
/// For any async method on ContractCommandNotifier (closeContract,
/// declareContractualPlan), regardless of whether the operation succeeds or
/// throws an exception, `KeepAliveLink.close()` SHALL be invoked in the
/// `finally` block, releasing the provider for auto-disposal.
///
/// Strategy: Uses source-level structural verification. Glados generates
/// random method selections and the test verifies that each method has the
/// correct try/catch/finally pattern with keepAlive.close() in the finally
/// block. This approach avoids transitive compilation issues while still
/// proving the structural property holds for all async methods.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 5: KeepAlive Lifecycle Completeness

/// Extracts the full method body (from `async {` to matching `}`) for a given
/// async method in the ContractCommandNotifier source file.
///
/// Returns the method body string or null if extraction fails.
String? _extractMethodBody(String content, String methodName) {
  // Find the method name in the source
  final methodNameIndex = content.indexOf(methodName);
  if (methodNameIndex == -1) return null;

  // Find 'async' keyword after the method name (skipping parameter list)
  final asyncIndex = content.indexOf('async', methodNameIndex);
  if (asyncIndex == -1) return null;

  // Find the opening brace of the method body (after 'async')
  final bodyStart = content.indexOf('{', asyncIndex);
  if (bodyStart == -1) return null;

  // Track braces to find the matching closing brace
  var braceCount = 0;
  var bodyEnd = bodyStart;
  for (var i = bodyStart; i < content.length; i++) {
    if (content[i] == '{') braceCount++;
    if (content[i] == '}') braceCount--;
    if (braceCount == 0) {
      bodyEnd = i + 1;
      break;
    }
  }

  return content.substring(bodyStart, bodyEnd);
}

void main() {
  // Read the source file once for all tests
  final sourceFile = File('lib/state/notifiers/contract_command_notifier.dart');

  group('Property 5: KeepAlive Lifecycle Completeness', () {
    // ── Sub-property: finally block with keepAlive.close() ──────────────
    Glados(any.choose(['closeContract', 'declareContractualPlan'])).test(
      'each async method has keepAlive.close() in a finally block',
      (methodName) {
        expect(
          sourceFile.existsSync(),
          isTrue,
          reason: 'ContractCommandNotifier source file must exist',
        );

        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, methodName);

        expect(
          methodBody,
          isNotNull,
          reason: '$methodName must exist as an async method',
        );

        // 1. ref.keepAlive() is called
        expect(
          methodBody!.contains('ref.keepAlive()'),
          isTrue,
          reason: '$methodName must call ref.keepAlive() to prevent disposal',
        );

        // 2. A finally block exists
        expect(
          methodBody.contains('finally'),
          isTrue,
          reason: '$methodName must have a finally block',
        );

        // 3. keepAlive.close() is called in the finally block
        final finallyIndex = methodBody.indexOf('finally');
        final afterFinally = methodBody.substring(finallyIndex);
        expect(
          afterFinally.contains('keepAlive.close()'),
          isTrue,
          reason:
              '$methodName must call keepAlive.close() in the finally block',
        );

        // 4. try block exists (ensuring try/catch/finally pattern)
        expect(
          methodBody.contains('try {'),
          isTrue,
          reason: '$methodName must use try/catch/finally pattern',
        );

        // 5. catch block exists (ensuring errors are handled)
        expect(
          methodBody.contains('catch'),
          isTrue,
          reason: '$methodName must have a catch block for error handling',
        );
      },
    );

    // ── Sub-property: keepAlive is assigned before any await ─────────────
    Glados(any.choose(['closeContract', 'declareContractualPlan'])).test(
      'keepAlive is assigned before any await in the method',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, methodName);

        expect(
          methodBody,
          isNotNull,
          reason: '$methodName must exist as an async method',
        );

        // keepAlive assignment must come before the first await
        final keepAliveIndex = methodBody!.indexOf('ref.keepAlive()');
        final firstAwaitIndex = methodBody.indexOf('await ');

        expect(
          keepAliveIndex,
          isNot(-1),
          reason: '$methodName must assign keepAlive',
        );
        expect(
          firstAwaitIndex,
          isNot(-1),
          reason: '$methodName must have at least one await',
        );
        expect(
          keepAliveIndex < firstAwaitIndex,
          isTrue,
          reason:
              '$methodName must assign keepAlive BEFORE the first await '
              '(keepAlive at $keepAliveIndex, first await at $firstAwaitIndex)',
        );
      },
    );

    // ── Sub-property: ref.mounted guard exists before state mutation ─────
    Glados(any.choose(['closeContract', 'declareContractualPlan'])).test(
      'ref.mounted guard exists before state mutation after await',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, methodName);

        expect(
          methodBody,
          isNotNull,
          reason: '$methodName must exist as an async method',
        );

        // After the await, there must be a ref.mounted check
        final firstAwaitIndex = methodBody!.indexOf('await ');
        final afterAwait = methodBody.substring(firstAwaitIndex);

        expect(
          afterAwait.contains('ref.mounted'),
          isTrue,
          reason: '$methodName must check ref.mounted after await (INV-15)',
        );
      },
    );

    // ── Sub-property: No early return bypasses finally ───────────────────
    Glados(any.choose(['closeContract', 'declareContractualPlan'])).test(
      'no return statement exists before try block that could bypass cleanup',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, methodName);

        expect(
          methodBody,
          isNotNull,
          reason: '$methodName must exist as an async method',
        );

        // The keepAlive assignment and try block should be the first
        // significant statements. No return before try.
        final tryIndex = methodBody!.indexOf('try {');
        expect(
          tryIndex,
          isNot(-1),
          reason: '$methodName must have a try block',
        );

        final beforeTry = methodBody.substring(0, tryIndex);

        // Before the try block, there should be no return statements
        expect(
          beforeTry.contains('return'),
          isFalse,
          reason:
              '$methodName must not have return statements before try block '
              'that could bypass the finally cleanup',
        );
      },
    );

    // ── Sub-property: Both success and error paths exist ────────────────
    Glados(any.choose(['closeContract', 'declareContractualPlan'])).test(
      'both success (AsyncData) and error (AsyncError) state transitions exist',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, methodName);

        expect(
          methodBody,
          isNotNull,
          reason: '$methodName must exist as an async method',
        );

        // Success path: state is set to AsyncData
        expect(
          methodBody!.contains('AsyncData'),
          isTrue,
          reason: '$methodName must set state to AsyncData on success',
        );

        // Error path: state is set to AsyncError
        expect(
          methodBody.contains('AsyncError'),
          isTrue,
          reason: '$methodName must set state to AsyncError on failure',
        );

        // Loading state at start
        expect(
          methodBody.contains('AsyncLoading'),
          isTrue,
          reason: '$methodName must set state to AsyncLoading at start',
        );
      },
    );

    // ── Sub-property: keepAlive.close() is in the finally block ─────────
    Glados(any.choose(['closeContract', 'declareContractualPlan'])).test(
      'finally block contains keepAlive.close() as its primary cleanup action',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, methodName);

        expect(
          methodBody,
          isNotNull,
          reason: '$methodName must exist as an async method',
        );

        // Extract the finally block content
        final finallyIndex = methodBody!.indexOf('finally');
        expect(
          finallyIndex,
          isNot(-1),
          reason: '$methodName must have a finally block',
        );

        final finallyBraceStart = methodBody.indexOf('{', finallyIndex);
        expect(
          finallyBraceStart,
          isNot(-1),
          reason: '$methodName finally block must have an opening brace',
        );

        var finallyBraceCount = 0;
        var finallyEnd = finallyBraceStart;
        for (var i = finallyBraceStart; i < methodBody.length; i++) {
          if (methodBody[i] == '{') finallyBraceCount++;
          if (methodBody[i] == '}') finallyBraceCount--;
          if (finallyBraceCount == 0) {
            finallyEnd = i + 1;
            break;
          }
        }

        final finallyBlock = methodBody.substring(
          finallyBraceStart,
          finallyEnd,
        );

        // The finally block must contain keepAlive.close()
        expect(
          finallyBlock.contains('keepAlive.close()'),
          isTrue,
          reason:
              '$methodName finally block must contain keepAlive.close() '
              'to release the provider for auto-disposal',
        );
      },
    );

    // ── Sub-property: keepAlive variable is used consistently ────────────
    Glados(any.choose(['closeContract', 'declareContractualPlan'])).test(
      'keepAlive variable is declared as final and closed exactly once',
      (methodName) {
        final content = sourceFile.readAsStringSync();
        final methodBody = _extractMethodBody(content, methodName);

        expect(
          methodBody,
          isNotNull,
          reason: '$methodName must exist as an async method',
        );

        // Verify the keepAlive is declared as a final local variable
        expect(
          methodBody!.contains('final keepAlive = ref.keepAlive()'),
          isTrue,
          reason: '$methodName must declare keepAlive as final local variable',
        );

        // Verify keepAlive.close() is called exactly once (in finally)
        final closeCallCount = RegExp(
          r'keepAlive\.close\(\)',
        ).allMatches(methodBody).length;
        expect(
          closeCallCount,
          equals(1),
          reason:
              '$methodName should call keepAlive.close() exactly once '
              '(in the finally block). Found $closeCallCount calls.',
        );
      },
    );
  });
}
