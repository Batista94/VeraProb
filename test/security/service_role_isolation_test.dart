/// Static-bundle isolation tests for INV-30 and INV-31.
///
/// **INV-30 (service_role isolation):** the Supabase service_role key MUST
/// never leak into the Flutter bundle. Read-side SuperAdmin operations are
/// routed through the `super-admin-proxy` Edge Function — the key lives only
/// in `Deno.env`.
///
/// **INV-31 (HMAC Zero-Knowledge):** SuperAdmin requests to the proxy must
/// be HMAC-signed by the Flutter client; the Edge Function must verify the
/// signature. These checks drive the TDD-red backlog: failing here is a
/// signal that INV-31 implementation is still pending in the proxy/repo.
///
/// Pure Dart — no Flutter binding required.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _libRoot = 'lib';
const _proxyIndexPath = 'supabase/functions/super-admin-proxy/index.ts';
const _hmacSharedPath = 'supabase/functions/shared/hmac_signer.ts';
const _superAdminRepoPath =
    'lib/infrastructure/super_admin/supabase_super_admin_repository.dart';

/// Removes Dart line comments (`// ...`, `/// ...`) and block comments
/// (`/* ... */`) so substring scans only inspect executable code.
String _stripDartComments(String source) {
  final withoutBlocks = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return withoutBlocks
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

/// Returns the body of the Dart method named [methodName] from [source],
/// using a brace-balanced scan starting at the method signature.
///
/// Returns an empty string if the method is not found — callers should fail
/// the test explicitly so the failure mode is obvious.
String _extractDartMethodBody(String source, String methodName) {
  // Anchor on `>` or whitespace before the method name to skip call sites.
  final pattern = RegExp('[>\\s]$methodName\\s*\\(', multiLine: true);
  final match = pattern.firstMatch(source);
  if (match == null) return '';

  // Walk past the parameter list `(...)` (paren-balanced — named params use
  // `{...}` inside, which would otherwise be mistaken for the method body).
  var depth = 1;
  var i = match.end;
  for (; i < source.length && depth > 0; i++) {
    final ch = source[i];
    if (ch == '(') depth++;
    if (ch == ')') depth--;
  }
  if (depth != 0) return '';

  // Now find the first `{` of the body and brace-balance to the close.
  final bodyOpen = source.indexOf('{', i);
  if (bodyOpen < 0) return '';
  depth = 0;
  for (var j = bodyOpen; j < source.length; j++) {
    final ch = source[j];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return source.substring(bodyOpen, j + 1);
    }
  }
  return '';
}

Iterable<File> _libDartFiles() sync* {
  final root = Directory(_libRoot);
  if (!root.existsSync()) return;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

void main() {
  group('INV-30 — service_role isolation in Flutter bundle', () {
    test('lib/**/*.dart contains NO non-comment service_role references', () {
      final offenders = <String>[];
      for (final file in _libDartFiles()) {
        final raw = file.readAsStringSync();
        final stripped = _stripDartComments(raw);
        if (stripped.contains('service_role')) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'INV-30 violation: Flutter bundle must never reference service_role '
            'in executable code. Offending files: $offenders',
      );
    });

    test(
      'getSystemAuditLog routes through super-admin-proxy and never service_role',
      () {
        final source = File(_superAdminRepoPath).readAsStringSync();
        final body = _extractDartMethodBody(source, 'getSystemAuditLog');
        expect(
          body,
          isNotEmpty,
          reason: 'getSystemAuditLog method not found at $_superAdminRepoPath',
        );
        expect(
          body,
          contains("'super-admin-proxy'"),
          reason: 'INV-30: read-side calls must go through the proxy.',
        );
        final stripped = _stripDartComments(body);
        expect(
          stripped.contains('service_role'),
          isFalse,
          reason: 'INV-30: service_role MUST NOT appear in executable repo code.',
        );
      },
    );
  });

  group('INV-31 — HMAC signing on super-admin-proxy', () {
    test(
      'getSystemAuditLog attaches HMAC signature + timestamp headers',
      skip: 'TDD-RED — implement HMAC headers in '
          'supabase_super_admin_repository.getSystemAuditLog (plan adendo A). '
          'Flip skip to false when impl lands.',
      () {
        final source = File(_superAdminRepoPath).readAsStringSync();
        final body = _extractDartMethodBody(source, 'getSystemAuditLog');
        expect(
          body,
          isNotEmpty,
          reason: 'getSystemAuditLog method not found at $_superAdminRepoPath',
        );
        expect(
          body,
          contains('x-veraprob-signature'),
          reason:
              'INV-31 (TDD-RED): client must HMAC-sign proxy requests. '
              'Add `x-veraprob-signature` header in functions.invoke. '
              'Backlog: implement before merge.',
        );
        expect(
          body,
          contains('x-veraprob-timestamp'),
          reason:
              'INV-31 (TDD-RED): client must include `x-veraprob-timestamp` '
              'header for replay protection (5-minute window). '
              'Backlog: implement before merge.',
        );
      },
    );

    test('super-admin-proxy index.ts imports HMAC verifier',
        skip: 'TDD-RED — implement HMAC verification in '
            'supabase/functions/super-admin-proxy/index.ts (plan adendo A). '
            'Flip skip to false when impl lands.', () {
      final proxyFile = File(_proxyIndexPath);
      expect(
        proxyFile.existsSync(),
        isTrue,
        reason: 'Edge Function not found at $_proxyIndexPath',
      );
      expect(
        File(_hmacSharedPath).existsSync(),
        isTrue,
        reason:
            'shared HMAC module not found at $_hmacSharedPath — INV-31 missing.',
      );

      final proxySource = proxyFile.readAsStringSync();
      final importsHmac =
          proxySource.contains('hmac_signer') ||
          proxySource.contains('verifyPayload');
      expect(
        importsHmac,
        isTrue,
        reason:
            'INV-31 (TDD-RED): super-admin-proxy must import verifyPayload '
            'from shared/hmac_signer.ts and reject unsigned/tampered requests. '
            'Backlog: implement HMAC verification path before merge.',
      );
    });
  });
}
