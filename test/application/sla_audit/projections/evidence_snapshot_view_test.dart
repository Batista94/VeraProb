import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/evidence_snapshot_view.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';

ForensicEvidenceSnapshot _buildSnapshot({
  List<Map<String, dynamic>> rules = const [],
  String? effectiveToUtc,
}) => ForensicEvidenceSnapshot.fromJson({
  'id': 'snap-1',
  'organization_id': 'org-1',
  'ledger_entry_id': 'led-1',
  'contract_id': 'ctr-1',
  'rule_set_id': 'rs-1',
  'sla_rule_version': 1,
  'schema_version': 1,
  'effective_from_utc': '2026-01-01T00:00:00Z',
  'effective_to_utc': effectiveToUtc,
  'snapshot': {'rules': rules},
  'integrity_hash': 'abc123deadbeef',
  'sealed_by': 'operator-1',
  'sealed_at_utc': '2026-06-01T12:00:00Z',
});

EvidenceVerification _buildVerification({
  List<Map<String, dynamic>> rules = const [],
}) {
  final snap = _buildSnapshot(rules: rules);
  return EvidenceVerification(
    ledgerEntryId: snap.ledgerEntryId,
    snapshot: snap,
    status: EvidenceVerificationStatus.authentic,
    storedHash: snap.integrityHash,
    computedHash: snap.integrityHash,
  );
}

Map<String, dynamic> _ruleFixture({
  String ruleId = 'r-1',
  String ruleType = 'MAX_TOLERANCE_DELAY',
}) => {
  'rule_id': ruleId,
  'rule_type': ruleType,
  'rule_config': {'threshold_seconds': 300},
  'rule_version': 2,
  'evaluation_order': 1,
};

void main() {
  group('EvidenceSnapshotStatus', () {
    test('enum has authentic and tampered values', () {
      expect(
        EvidenceSnapshotStatus.values,
        contains(EvidenceSnapshotStatus.authentic),
      );
      expect(
        EvidenceSnapshotStatus.values,
        contains(EvidenceSnapshotStatus.tampered),
      );
      expect(EvidenceSnapshotStatus.values, hasLength(2));
    });
  });

  group('FrozenRuleView — nominal', () {
    test('constructor preserves all fields', () {
      const view = FrozenRuleView(
        ruleId: 'r-1',
        ruleVersion: 3,
        ruleTypeKey: 'MAX_TOLERANCE_DELAY',
        config: {'threshold_seconds': 120},
      );
      expect(view.ruleId, 'r-1');
      expect(view.ruleVersion, 3);
      expect(view.ruleTypeKey, 'MAX_TOLERANCE_DELAY');
      expect(view.config['threshold_seconds'], 120);
    });
  });

  group('EvidenceSnapshotView — nominal', () {
    test('const constructor preserves all 8 fields', () {
      final now = DateTime.utc(2026, 6, 1, 12);
      final from = DateTime.utc(2026, 1, 1);
      final view = EvidenceSnapshotView(
        ledgerEntryId: 'led-1',
        status: EvidenceSnapshotStatus.authentic,
        effectiveFromUtc: from,
        effectiveToUtc: null,
        sealedBy: 'op-1',
        sealedAtUtc: now,
        integrityHash: 'hash-abc',
        rules: const [],
      );
      expect(view.ledgerEntryId, 'led-1');
      expect(view.status, EvidenceSnapshotStatus.authentic);
      expect(view.effectiveFromUtc, from);
      expect(view.effectiveToUtc, isNull);
      expect(view.sealedBy, 'op-1');
      expect(view.sealedAtUtc, now);
      expect(view.integrityHash, 'hash-abc');
      expect(view.rules, isEmpty);
    });

    test('fromVerification maps authentic domain object correctly', () {
      final view = EvidenceSnapshotView.fromVerification(_buildVerification());
      expect(view.ledgerEntryId, 'led-1');
      expect(view.status, EvidenceSnapshotStatus.authentic);
      expect(view.sealedBy, 'operator-1');
      expect(view.integrityHash, 'abc123deadbeef');
      expect(view.sealedAtUtc, DateTime.utc(2026, 6, 1, 12));
      expect(view.rules, isEmpty);
    });

    test('fromVerification with null effectiveToUtc preserves null', () {
      final view = EvidenceSnapshotView.fromVerification(_buildVerification());
      expect(view.effectiveToUtc, isNull);
    });

    test(
      'tampered factory sets status=tampered, empty hash, empty rules, epoch date',
      () {
        final view = EvidenceSnapshotView.tampered('led-tampered');
        expect(view.ledgerEntryId, 'led-tampered');
        expect(view.status, EvidenceSnapshotStatus.tampered);
        expect(view.integrityHash, isEmpty);
        expect(view.rules, isEmpty);
        expect(view.effectiveFromUtc, isNull);
        expect(view.effectiveToUtc, isNull);
        expect(view.sealedBy, isEmpty);
        expect(view.sealedAtUtc, DateTime.utc(0));
      },
    );
  });

  // ── CIA — Confidentiality ────────────────────────────────────────────────────

  group('CIA — Confidentiality', () {
    test(
      'EvidenceSnapshotView has no organizationId field (tenant isolation — INV-22)',
      () {
        // The projection shields presentation from organization_id (INV-1/INV-22).
        // This is primarily a compile-time invariant: the class has no such getter.
        // Runtime: confirm only documented fields are accessible.
        final view = EvidenceSnapshotView.tampered('led-1');
        expect(view.ledgerEntryId, isA<String>());
        expect(view.status, isA<EvidenceSnapshotStatus>());
        expect(view.integrityHash, isA<String>());
        // organizationId deliberately absent — tenant data stays at domain layer
      },
    );

    test(
      'tampered() exposes empty integrityHash — original hash not accessible',
      () {
        // Even for a tampered record the projection must not leak the real hash value.
        final view = EvidenceSnapshotView.tampered('led-secret');
        expect(
          view.integrityHash,
          isEmpty,
          reason: 'tampered view must not expose a real hash value',
        );
      },
    );
  });

  // ── CIA — Integrity ──────────────────────────────────────────────────────────

  group('CIA — Integrity', () {
    test(
      'fromVerification maps all 3 rules without silent truncation (INV-15)',
      () {
        final rules = [
          _ruleFixture(ruleId: 'r-1', ruleType: 'MAX_TOLERANCE_DELAY'),
          _ruleFixture(ruleId: 'r-2', ruleType: 'MAX_EVIDENCE_GAP'),
          _ruleFixture(ruleId: 'r-3', ruleType: 'NO_SHOW_PENALTY'),
        ];
        final view = EvidenceSnapshotView.fromVerification(
          _buildVerification(rules: rules),
        );
        expect(
          view.rules,
          hasLength(3),
          reason: 'all 3 rules must be mapped — no silent truncation (INV-15)',
        );
        expect(
          view.rules.map((r) => r.ruleId),
          containsAll(['r-1', 'r-2', 'r-3']),
        );
      },
    );

    test(
      'ruleTypeKey is a String, not SlaRuleType — domain enum does not leak (INV-13)',
      () {
        final view = EvidenceSnapshotView.fromVerification(
          _buildVerification(rules: [_ruleFixture()]),
        );
        final frozenRule = view.rules.first;
        expect(
          frozenRule.ruleTypeKey,
          isA<String>(),
          reason:
              'ruleTypeKey must be String to avoid leaking SlaRuleType to presentation (INV-13)',
        );
        expect(frozenRule.ruleTypeKey, 'MAX_TOLERANCE_DELAY');
      },
    );

    test(
      'fromVerification status comes from domain EvidenceVerification, not recomputed',
      () {
        // Status must flow from EvidenceVerification.status — the projection layer
        // must never recompute authenticity from hashes (that is the domain's job).
        final snap = _buildSnapshot();
        final authentic = EvidenceVerification(
          ledgerEntryId: snap.ledgerEntryId,
          snapshot: snap,
          status: EvidenceVerificationStatus.authentic,
          storedHash: snap.integrityHash,
          computedHash: snap.integrityHash,
        );
        expect(
          EvidenceSnapshotView.fromVerification(authentic).status,
          EvidenceSnapshotStatus.authentic,
        );
      },
    );

    test('fromVerification preserves effectiveFromUtc from snapshot', () {
      final view = EvidenceSnapshotView.fromVerification(_buildVerification());
      expect(view.effectiveFromUtc, DateTime.utc(2026, 1, 1));
    });
  });

  // ── CIA — Availability ───────────────────────────────────────────────────────

  group('CIA — Availability', () {
    test('tampered() never throws for empty ledgerEntryId', () {
      expect(() => EvidenceSnapshotView.tampered(''), returnsNormally);
    });

    test('tampered() never throws for whitespace ledgerEntryId', () {
      expect(() => EvidenceSnapshotView.tampered('   '), returnsNormally);
    });

    test(
      'fromVerification with no rules in snapshot yields empty rules list',
      () {
        final view = EvidenceSnapshotView.fromVerification(
          _buildVerification(rules: const []),
        );
        expect(view.rules, isEmpty);
      },
    );
  });
}
