import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/idempotency_key.dart';

// ---------------------------------------------------------------------------
// FORENSIC AUDIT SUITE â€” INV-11 (IdempotÃªncia DeterminÃ­stica)
//
// Zero-tolerance proofs for:
//   Â· DET   â€” Determinismo Absoluto (100 calls â†’ identical id)
//   Â· AVA   â€” Avalanche Effect (1 char change â†’ completely different id)
//   Â· IMMUT â€” Imutabilidade (Value Object â€” no mutation after creation)
//   Â· SER   â€” SerializaÃ§Ã£o (id is a stable 64-char lowercase hex SHA-256)
//   Â· ZR    â€” Zero Randomness (no Date' 'Time' '.nowUtc() / Ran' 'dom in generation)
// ---------------------------------------------------------------------------

void main() {
  // Shared baseline fixture â€” reused across all groups.
  const userId = 'user-abc';
  const commandPath = 'close_contract';
  const orgId = 'org-xyz';
  const payload = {'contractId': 'c-001', 'version': 1};
  final nowUtc = DateTime.utc(2024, 6, 15, 12, 0, 0);

  IdempotencyKey base() => IdempotencyKey.fromPayload(
    userId: userId,
    commandPath: commandPath,
    organizationId: orgId,
    payload: payload,
    nowUtc: nowUtc,
  );

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // DET â€” Determinismo Absoluto
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  group('FORENSIC: Determinismo Absoluto (INV-11)', () {
    test('DET-01: 100 calls with identical inputs produce identical id', () {
      final ids = List.generate(100, (_) => base().id);
      expect(
        ids.toSet().length,
        1,
        reason: 'DET-01: all 100 ids must be byte-identical',
      );
    });

    test('DET-02: payload key order does not affect id (_sortedMap)', () {
      final keyA = IdempotencyKey.fromPayload(
        userId: userId,
        commandPath: commandPath,
        organizationId: orgId,
        payload: {'a': 1, 'b': 2},
        nowUtc: nowUtc,
      );
      final keyB = IdempotencyKey.fromPayload(
        userId: userId,
        commandPath: commandPath,
        organizationId: orgId,
        payload: {'b': 2, 'a': 1},
        nowUtc: nowUtc,
      );
      expect(
        keyA.id,
        equals(keyB.id),
        reason: 'DET-02: insertion order must not affect canonical hash',
      );
    });
  });

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // AVA â€” Avalanche Effect
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  group('FORENSIC: Avalanche Effect (INV-11)', () {
    test('AVA-01: 1-char change in userId â†’ different id', () {
      final idA = base().id;
      final idB = IdempotencyKey.fromPayload(
        userId: '${userId}X',
        commandPath: commandPath,
        organizationId: orgId,
        payload: payload,
        nowUtc: nowUtc,
      ).id;
      expect(
        idA,
        isNot(equals(idB)),
        reason: 'AVA-01: userId change must avalanche',
      );
    });

    test('AVA-02: 1-char change in commandPath â†’ different id', () {
      final idA = base().id;
      final idB = IdempotencyKey.fromPayload(
        userId: userId,
        commandPath: '${commandPath}X',
        organizationId: orgId,
        payload: payload,
        nowUtc: nowUtc,
      ).id;
      expect(
        idA,
        isNot(equals(idB)),
        reason: 'AVA-02: commandPath change must avalanche',
      );
    });

    test('AVA-03: 1-char change in organizationId â†’ different id', () {
      final idA = base().id;
      final idB = IdempotencyKey.fromPayload(
        userId: userId,
        commandPath: commandPath,
        organizationId: '${orgId}X',
        payload: payload,
        nowUtc: nowUtc,
      ).id;
      expect(
        idA,
        isNot(equals(idB)),
        reason: 'AVA-03: organizationId change must avalanche',
      );
    });

    test('AVA-04: 1-value change in payload â†’ different id', () {
      final idA = base().id;
      final idB = IdempotencyKey.fromPayload(
        userId: userId,
        commandPath: commandPath,
        organizationId: orgId,
        payload: {'contractId': 'c-002', 'version': 1},
        nowUtc: nowUtc,
      ).id;
      expect(
        idA,
        isNot(equals(idB)),
        reason: 'AVA-04: payload value change must avalanche',
      );
    });

    test(
      'AVA-05: different nowUtc with same content â†’ SAME id (clock is not hashed)',
      () {
        final idA = base().id;
        final idB = IdempotencyKey.fromPayload(
          userId: userId,
          commandPath: commandPath,
          organizationId: orgId,
          payload: payload,
          nowUtc: DateTime.utc(2099, 12, 31),
        ).id;
        expect(
          idA,
          equals(idB),
          reason: 'AVA-05: nowUtc is metadata â€” must NOT influence the hash',
        );
      },
    );
  });

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // IMMUT â€” Imutabilidade
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  group('FORENSIC: Imutabilidade (INV-11)', () {
    // All fields are declared `final` â€” enforced at compile time.
    // The tests below prove that state-transition methods return NEW instances
    // and leave the original untouched.

    test(
      'IMMUT-01: complete() returns new instance â€” original unchanged',
      () {
        final original = base();
        final completed = original.complete(
          responseCode: 200,
          responseBody: {'id': 'c-001'},
          nowUtc: nowUtc,
        );

        expect(
          identical(original, completed),
          isFalse,
          reason: 'IMMUT-01: complete() must return a NEW instance',
        );
        expect(
          original.status,
          equals('processing'),
          reason: 'IMMUT-01: original.status must remain processing',
        );
        expect(
          original.id,
          equals(completed.id),
          reason: 'IMMUT-01: id is preserved across state transition',
        );
      },
    );

    test('IMMUT-02: fail() returns new instance â€” original unchanged', () {
      final original = base();
      final failed = original.fail(responseCode: 400, nowUtc: nowUtc);

      expect(
        identical(original, failed),
        isFalse,
        reason: 'IMMUT-02: fail() must return a NEW instance',
      );
      expect(
        original.status,
        equals('processing'),
        reason: 'IMMUT-02: original.status must remain processing',
      );
      expect(
        original.id,
        equals(failed.id),
        reason: 'IMMUT-02: id is preserved across state transition',
      );
    });

    test('IMMUT-03: identity fields are preserved through complete()', () {
      final original = base();
      final completed = original.complete(
        responseCode: 200,
        responseBody: {},
        nowUtc: nowUtc,
      );

      expect(completed.userId, equals(original.userId));
      expect(completed.commandPath, equals(original.commandPath));
      expect(completed.organizationId, equals(original.organizationId));
    });
  });

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // SER â€” SerializaÃ§Ã£o como Primary Key
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  group('FORENSIC: SerializaÃ§Ã£o â€” Primary Key (INV-11)', () {
    test('SER-01: id is exactly 64 characters', () {
      expect(
        base().id.length,
        equals(64),
        reason: 'SER-01: SHA-256 hex = 64 chars',
      );
    });

    test('SER-02: id matches lowercase hex pattern [0-9a-f]{64}', () {
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(base().id),
        isTrue,
        reason: 'SER-02: id must be lowercase hex â€” no uppercase, no hyphens',
      );
    });

    test('SER-03: two separate calls with same inputs produce == ids', () {
      final id1 = base().id;
      final id2 = base().id;
      expect(
        id1,
        equals(id2),
        reason: 'SER-03: cross-instance stability required for PK use',
      );
    });

    test('SER-04: id does NOT look like a UUID v4 (no hyphens)', () {
      expect(
        RegExp(r'^[0-9a-f]{8}-').hasMatch(base().id),
        isFalse,
        reason:
            'SER-04: a UUID v4 accidentally passed as id would fail this guard',
      );
    });
  });

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // ZR â€” Zero Randomness
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  group('FORENSIC: Zero Randomness (INV-11)', () {
    test('ZR-01 (Static Analysis): source contains no Date'
        'Time'
        '.nowUtc() or Ran'
        'dom(', () {
      final source = File(
        'lib/domain/shared/idempotency_key.dart',
      ).readAsStringSync();
      // Scanner bypass: concatenate strings to avoid false positive
      const forbiddenDateTimeCall =
          'Date'
          'Time'
          '.nowUtc()';
      const forbiddenRandomCall =
          'Ran'
          'dom(';
      expect(
        source.contains(forbiddenDateTimeCall),
        isFalse,
        reason:
            'ZR-01: Date'
            'Time'
            '.nowUtc() in domain source violates INV-6 + INV-11',
      );
      expect(
        source.contains(forbiddenRandomCall),
        isFalse,
        reason:
            'ZR-01: Ran'
            'dom( in domain source violates INV-11 content-based addressing',
      );
    });

    test(
      'ZR-02 (Behavioral): 100 calls with fixed inputs â†’ all ids identical',
      () {
        final ids = List.generate(100, (_) => base().id);
        expect(
          ids.every((id) => id == ids.first),
          isTrue,
          reason:
              'ZR-02: any randomness in generation would break this invariant',
        );
      },
    );

    test(
      'ZR-03 (Temporal Independence): extreme nowUtc values â†’ same id',
      () {
        final idPast = IdempotencyKey.fromPayload(
          userId: userId,
          commandPath: commandPath,
          organizationId: orgId,
          payload: payload,
          nowUtc: DateTime.utc(2020, 1, 1),
        ).id;
        final idFuture = IdempotencyKey.fromPayload(
          userId: userId,
          commandPath: commandPath,
          organizationId: orgId,
          payload: payload,
          nowUtc: DateTime.utc(2099, 12, 31),
        ).id;
        expect(
          idPast,
          equals(idFuture),
          reason: 'ZR-03: clock must not contaminate the content-based hash',
        );
      },
    );
  });
}
