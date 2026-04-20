import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Red Team Test — HMAC Tampering Detection (INV-31 + INV-9)
///
/// **Attack Scenario:**
/// An attacker (or malicious DBA) modifies a financial record in the database
/// after it was inserted. The HMAC signature stored alongside the record
/// no longer matches the recomputed signature from the tampered payload.
///
/// **What this test proves:**
/// 1. Canonical JSON is deterministic — same payload → same hash
/// 2. Single-bit change → completely different hash (avalanche effect)
/// 3. The `_sortKeys` recursion is complete — nested changes are detected
/// 4. DateTime normalization is consistent — temporal fields don't cause false positives
///
/// **In production**, the `IntegrityVerificationService` would:
/// - Read the record from DB
/// - Recompute the hash from the stored payload
/// - Compare with the stored HMAC signature
/// - Throw `IntegrityException` on mismatch
void main() {
  group('Red Team: HMAC Tampering Detection', () {
    test('single-field tamming is detected (avalanche effect)', () {
      // Original legitimate payload
      final originalPayload = <String, dynamic>{
        'organization_id': 'org-123',
        'contract_id': 'ctr-456',
        'amount_cents': 50000,
        'timestamp': DateTime.utc(2026, 4, 11, 15, 30, 0),
        'metadata': {'reviewer': 'alice', 'approved': true},
      };

      final originalHash = BasePostgresRepository.hashPayload(originalPayload);
      expect(originalHash, isNotNull);

      // ── ATTACK 1: Change financial value ──
      final tamperedAmount = <String, dynamic>{
        'organization_id': 'org-123',
        'contract_id': 'ctr-456',
        'amount_cents': 5000, // Attacker changed 50000 → 5000
        'timestamp': DateTime.utc(2026, 4, 11, 15, 30, 0),
        'metadata': {'reviewer': 'alice', 'approved': true},
      };

      final tamperedHash = BasePostgresRepository.hashPayload(tamperedAmount);
      expect(tamperedHash, isNotNull);
      expect(
        originalHash,
        isNot(equals(tamperedHash)),
        reason:
            'ATTACK DETECTED: Changing amount_cents must produce different hash',
      );

      // Verify avalanche: hashes should be completely different
      // (not just a few chars different)
      int diffCount = 0;
      for (int i = 0; i < originalHash!.length; i++) {
        if (originalHash[i] != tamperedHash![i]) diffCount++;
      }
      expect(
        diffCount,
        greaterThan(20),
        reason:
            'Avalanche effect: most chars should differ after single-bit change',
      );
    });

    test('nested-field tampering is detected (recursive sort)', () {
      final originalPayload = <String, dynamic>{
        'ledger_entry_id': 'le-789',
        'organization_id': 'org-123',
        'events': [
          {
            'type': 'sla_breach',
            'severity': 'critical',
            'timestamp': DateTime.utc(2026, 4, 11),
            'details': {'threshold_ms': 5000, 'actual_ms': 12000},
          },
        ],
      };

      final originalHash = BasePostgresRepository.hashPayload(originalPayload);

      // ── ATTACK 2: Change nested severity ──
      final tamperedPayload = <String, dynamic>{
        'ledger_entry_id': 'le-789',
        'organization_id': 'org-123',
        'events': [
          {
            'type': 'sla_breach',
            'severity': 'low', // Attacker downgraded severity
            'timestamp': DateTime.utc(2026, 4, 11),
            'details': {'threshold_ms': 5000, 'actual_ms': 12000},
          },
        ],
      };

      final tamperedHash = BasePostgresRepository.hashPayload(tamperedPayload);

      expect(
        originalHash,
        isNot(equals(tamperedHash)),
        reason:
            'ATTACK DETECTED: Changing nested severity must produce different hash',
      );
    });

    test('inserting extra field into list is detected', () {
      final originalPayload = <String, dynamic>{
        'batch_id': 'batch-001',
        'items': [
          {'id': 'item-1', 'value': 100},
          {'id': 'item-2', 'value': 200},
        ],
      };

      final originalHash = BasePostgresRepository.hashPayload(originalPayload);

      // ── ATTACK 3: Insert fraudulent item ──
      final tamperedPayload = <String, dynamic>{
        'batch_id': 'batch-001',
        'items': [
          {'id': 'item-1', 'value': 100},
          {'id': 'item-2', 'value': 200},
          {'id': 'item-fraud', 'value': 999999}, // Injected!
        ],
      };

      final tamperedHash = BasePostgresRepository.hashPayload(tamperedPayload);

      expect(
        originalHash,
        isNot(equals(tamperedHash)),
        reason: 'ATTACK DETECTED: Injecting extra list item must change hash',
      );
    });

    test('DateTime tampering is detected', () {
      final originalPayload = <String, dynamic>{
        'verdict_id': 'v-001',
        'organization_id': 'org-123',
        'evaluated_at': DateTime.utc(2026, 4, 11, 15, 30, 0),
        'result': 'breach',
        'penalty_cents': 25000,
      };

      final originalHash = BasePostgresRepository.hashPayload(originalPayload);

      // ── ATTACK 4: Shift evaluation timestamp ──
      final tamperedPayload = <String, dynamic>{
        'verdict_id': 'v-001',
        'organization_id': 'org-123',
        'evaluated_at': DateTime.utc(
          2026,
          4,
          10,
          15,
          30,
          0,
        ), // Moved 1 day back
        'result': 'breach',
        'penalty_cents': 25000,
      };

      final tamperedHash = BasePostgresRepository.hashPayload(tamperedPayload);

      expect(
        originalHash,
        isNot(equals(tamperedHash)),
        reason:
            'ATTACK DETECTED: Changing DateTime must produce different hash',
      );
    });

    test('original payload verifies against itself (no false positive)', () {
      final payload = <String, dynamic>{
        'organization_id': 'org-123',
        'contract_id': 'ctr-456',
        'amount_cents': 50000,
        'timestamp': DateTime.utc(2026, 4, 11, 15, 30, 0),
        'metadata': {'reviewer': 'alice', 'approved': true},
      };

      final hash1 = BasePostgresRepository.hashPayload(payload);
      final hash2 = BasePostgresRepository.hashPayload(payload);

      expect(
        hash1,
        equals(hash2),
        reason: 'NO FALSE POSITIVE: Same payload must ALWAYS produce same hash',
      );
    });

    test('key order does NOT affect hash (canonical JSON works)', () {
      // Same data, different insertion order
      final payloadA = <String, dynamic>{
        'z_field': 'end',
        'a_field': 'start',
        'nested': {'z': 1, 'a': 2},
      };
      final payloadB = <String, dynamic>{
        'nested': {'a': 2, 'z': 1},
        'a_field': 'start',
        'z_field': 'end',
      };

      final hashA = BasePostgresRepository.hashPayload(payloadA);
      final hashB = BasePostgresRepository.hashPayload(payloadB);

      expect(
        hashA,
        equals(hashB),
        reason:
            'Canonical JSON: key order must not affect hash — keys are sorted',
      );
    });

    test(
      'deeply nested tampering is detected (map > list > map > list > map)',
      () {
        final originalPayload = <String, dynamic>{
          'root': {
            'level1': [
              {
                'level2': [
                  {
                    'level3': {'target': 'ORIGINAL', 'z_key': 1, 'a_key': 2},
                  },
                ],
              },
            ],
          },
        };

        final originalHash = BasePostgresRepository.hashPayload(
          originalPayload,
        );

        // ── ATTACK 5: Change deepest value ──
        final tamperedPayload = <String, dynamic>{
          'root': {
            'level1': [
              {
                'level2': [
                  {
                    'level3': {'target': 'TAMPERED', 'z_key': 1, 'a_key': 2},
                  },
                ],
              },
            ],
          },
        };

        final tamperedHash = BasePostgresRepository.hashPayload(
          tamperedPayload,
        );

        expect(
          originalHash,
          isNot(equals(tamperedHash)),
          reason:
              'ATTACK DETECTED: Changing value at depth 5 must produce different hash',
        );
      },
    );
  });
}
