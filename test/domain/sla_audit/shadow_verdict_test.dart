import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/shadow_verdict.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  // ── Shared fixtures ────────────────────────────────────────────────────────

  final baseTime = DateTime.utc(2026, 6, 1, 10, 0);

  VerdictEvidence makeEvidence() => VerdictEvidence.create(
    clauseRef: 'no-show-clause-1',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5505,
    primaryEvidenceLng: -46.6333,
    primaryEvidenceTimestampUtc: baseTime,
    deltaValue: 15.0,
    thresholdValue: 0.0,
    fineCents: const Money(150000),
    confidenceScore: 100,
  );

  ShadowVerdict makeVerdict({String engineVerdict = 'noShow'}) =>
      ShadowVerdict.fromEngineResult(
        organizationId: 'org-uuid-001',
        setId: 'set-001',
        contractId: 'contract-001',
        engineVerdict: engineVerdict,
        engineVerdictAtUtc: baseTime,
        engineVersion: 'veraprob-core_v4',
        verdictEvidence: makeEvidence(),
        createdAtUtc: baseTime,
      );

  final reviewTime = DateTime.utc(2026, 6, 2, 8, 0);
  const reviewer = 'auditor-uuid-001';

  // ── fromEngineResult — validations ────────────────────────────────────────

  group('fromEngineResult — validations', () {
    test('rejects empty organizationId', () {
      expect(
        () => ShadowVerdict.fromEngineResult(
          organizationId: '',
          setId: 'set-001',
          contractId: 'contract-001',
          engineVerdict: 'noShow',
          engineVerdictAtUtc: baseTime,
          engineVersion: 'v3',
          verdictEvidence: makeEvidence(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects empty setId', () {
      expect(
        () => makeVerdict()
            .withManualVerdict(
              manualVerdict: 'applied',
              manualVerdictAtUtc: reviewTime,
              manualReviewedBy: reviewer,
            )
            .divergenceType,
        returnsNormally,
      );
      expect(
        () => ShadowVerdict.fromEngineResult(
          organizationId: 'org-001',
          setId: '',
          contractId: 'contract-001',
          engineVerdict: 'noShow',
          engineVerdictAtUtc: baseTime,
          engineVersion: 'v3',
          verdictEvidence: makeEvidence(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects empty contractId', () {
      expect(
        () => ShadowVerdict.fromEngineResult(
          organizationId: 'org-001',
          setId: 'set-001',
          contractId: '',
          engineVerdict: 'noShow',
          engineVerdictAtUtc: baseTime,
          engineVersion: 'v3',
          verdictEvidence: makeEvidence(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects invalid engineVerdict value', () {
      expect(
        () => ShadowVerdict.fromEngineResult(
          organizationId: 'org-001',
          setId: 'set-001',
          contractId: 'contract-001',
          engineVerdict: 'guilty',
          engineVerdictAtUtc: baseTime,
          engineVersion: 'v3',
          verdictEvidence: makeEvidence(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects non-UTC engineVerdictAtUtc', () {
      expect(
        () => ShadowVerdict.fromEngineResult(
          organizationId: 'org-001',
          setId: 'set-001',
          contractId: 'contract-001',
          engineVerdict: 'noShow',
          engineVerdictAtUtc: DateTime(2026, 6, 1, 10, 0), // local time
          engineVersion: 'v3',
          verdictEvidence: makeEvidence(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects empty engineVersion', () {
      expect(
        () => ShadowVerdict.fromEngineResult(
          organizationId: 'org-001',
          setId: 'set-001',
          contractId: 'contract-001',
          engineVerdict: 'noShow',
          engineVerdictAtUtc: baseTime,
          engineVersion: '',
          verdictEvidence: makeEvidence(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('all valid engine verdicts are accepted', () {
      for (final v in ['executed', 'noShow', 'evidenceGap', 'inhibited']) {
        expect(() => makeVerdict(engineVerdict: v), returnsNormally);
      }
    });

    test('initial divergenceType is pendingManual', () {
      expect(makeVerdict().divergenceType, ShadowDivergenceType.pendingManual);
    });
  });

  // ── traceabilityHash — determinism (INV-22) ───────────────────────────────

  group('traceabilityHash — determinism', () {
    test('same inputs produce identical hash', () {
      final a = makeVerdict();
      final b = makeVerdict();
      expect(a.traceabilityHash, equals(b.traceabilityHash));
    });

    test('different setId changes hash', () {
      final a = ShadowVerdict.fromEngineResult(
        organizationId: 'org-001',
        setId: 'set-A',
        contractId: 'contract-001',
        engineVerdict: 'noShow',
        engineVerdictAtUtc: baseTime,
        engineVersion: 'v3',
        verdictEvidence: makeEvidence(),
      );
      final b = ShadowVerdict.fromEngineResult(
        organizationId: 'org-001',
        setId: 'set-B',
        contractId: 'contract-001',
        engineVerdict: 'noShow',
        engineVerdictAtUtc: baseTime,
        engineVersion: 'v3',
        verdictEvidence: makeEvidence(),
      );
      expect(a.traceabilityHash, isNot(equals(b.traceabilityHash)));
    });

    test('different engineVersion changes hash', () {
      final a = ShadowVerdict.fromEngineResult(
        organizationId: 'org-001',
        setId: 'set-001',
        contractId: 'contract-001',
        engineVerdict: 'noShow',
        engineVerdictAtUtc: baseTime,
        engineVersion: 'v3',
        verdictEvidence: makeEvidence(),
      );
      final b = ShadowVerdict.fromEngineResult(
        organizationId: 'org-001',
        setId: 'set-001',
        contractId: 'contract-001',
        engineVerdict: 'noShow',
        engineVerdictAtUtc: baseTime,
        engineVersion: 'v4',
        verdictEvidence: makeEvidence(),
      );
      expect(a.traceabilityHash, isNot(equals(b.traceabilityHash)));
    });

    test('different engineVerdict changes hash', () {
      final a = makeVerdict(engineVerdict: 'noShow');
      final b = makeVerdict(engineVerdict: 'executed');
      expect(a.traceabilityHash, isNot(equals(b.traceabilityHash)));
    });
  });

  // ── withManualVerdict — divergence classification ─────────────────────────

  group('withManualVerdict — divergence classification', () {
    ShadowVerdict classify(String engineVerdict, String manualVerdict) =>
        makeVerdict(engineVerdict: engineVerdict).withManualVerdict(
          manualVerdict: manualVerdict,
          manualVerdictAtUtc: reviewTime,
          manualReviewedBy: reviewer,
        );

    // executed
    test('executed + applied → match', () {
      expect(
        classify('executed', 'applied').divergenceType,
        ShadowDivergenceType.match,
      );
    });

    test('executed + rejected → falsePositive', () {
      expect(
        classify('executed', 'rejected').divergenceType,
        ShadowDivergenceType.falsePositive,
      );
    });

    // noShow
    test('noShow + applied → match', () {
      expect(
        classify('noShow', 'applied').divergenceType,
        ShadowDivergenceType.match,
      );
    });

    test('noShow + rejected → falsePositive', () {
      expect(
        classify('noShow', 'rejected').divergenceType,
        ShadowDivergenceType.falsePositive,
      );
    });

    // evidenceGap
    test('evidenceGap + rejected → match', () {
      expect(
        classify('evidenceGap', 'rejected').divergenceType,
        ShadowDivergenceType.match,
      );
    });

    test('evidenceGap + applied → falseNegative', () {
      expect(
        classify('evidenceGap', 'applied').divergenceType,
        ShadowDivergenceType.falseNegative,
      );
    });

    // inhibited — refined logic
    test('inhibited + rejected → match (engine correctly suppressed)', () {
      expect(
        classify('inhibited', 'rejected').divergenceType,
        ShadowDivergenceType.match,
      );
    });

    test(
      'inhibited + applied → falseNegative (engine too lenient — INV-15 violation candidate)',
      () {
        expect(
          classify('inhibited', 'applied').divergenceType,
          ShadowDivergenceType.falseNegative,
        );
      },
    );
  });

  // ── withManualVerdict — engine fields are immutable ───────────────────────

  group('withManualVerdict — engine fields preserved', () {
    test('traceabilityHash unchanged after manual verdict', () {
      final original = makeVerdict();
      final updated = original.withManualVerdict(
        manualVerdict: 'applied',
        manualVerdictAtUtc: reviewTime,
        manualReviewedBy: reviewer,
      );
      expect(updated.traceabilityHash, equals(original.traceabilityHash));
    });

    test('engineVerdict unchanged after manual verdict', () {
      final original = makeVerdict(engineVerdict: 'noShow');
      final updated = original.withManualVerdict(
        manualVerdict: 'rejected',
        manualVerdictAtUtc: reviewTime,
        manualReviewedBy: reviewer,
      );
      expect(updated.engineVerdict, equals('noShow'));
    });

    test('engineVersion unchanged after manual verdict', () {
      final original = makeVerdict();
      final updated = original.withManualVerdict(
        manualVerdict: 'applied',
        manualVerdictAtUtc: reviewTime,
        manualReviewedBy: reviewer,
      );
      expect(updated.engineVersion, equals(original.engineVersion));
    });

    test('rejects non-UTC manualVerdictAtUtc', () {
      expect(
        () => makeVerdict().withManualVerdict(
          manualVerdict: 'applied',
          manualVerdictAtUtc: DateTime(2026, 6, 2, 8, 0), // local time
          manualReviewedBy: reviewer,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('manual fields are populated on updated copy', () {
      final updated = makeVerdict().withManualVerdict(
        manualVerdict: 'rejected',
        manualVerdictAtUtc: reviewTime,
        manualReviewedBy: reviewer,
      );
      expect(updated.manualVerdict, equals('rejected'));
      expect(updated.manualVerdictAtUtc, equals(reviewTime));
      expect(updated.manualReviewedBy, equals(reviewer));
    });
  });

  // ── fromJson / toJson — round-trip ────────────────────────────────────────

  group('fromJson / toJson — round-trip', () {
    test('round-trip preserves all fields', () {
      final original = makeVerdict().withManualVerdict(
        manualVerdict: 'applied',
        manualVerdictAtUtc: reviewTime,
        manualReviewedBy: reviewer,
      );
      final restored = ShadowVerdict.fromJson(original.toJson());

      expect(restored.id, equals(original.id));
      expect(restored.organizationId, equals(original.organizationId));
      expect(restored.setId, equals(original.setId));
      expect(restored.contractId, equals(original.contractId));
      expect(restored.engineVerdict, equals(original.engineVerdict));
      expect(restored.engineVerdictAtUtc, equals(original.engineVerdictAtUtc));
      expect(restored.engineVersion, equals(original.engineVersion));
      expect(restored.traceabilityHash, equals(original.traceabilityHash));
      expect(restored.divergenceType, equals(original.divergenceType));
      expect(restored.manualVerdict, equals(original.manualVerdict));
      expect(restored.manualVerdictAtUtc, equals(original.manualVerdictAtUtc));
      expect(restored.manualReviewedBy, equals(original.manualReviewedBy));
    });

    test('pendingManual divergence survives round-trip', () {
      final original = makeVerdict();
      final restored = ShadowVerdict.fromJson(original.toJson());
      expect(restored.divergenceType, ShadowDivergenceType.pendingManual);
    });

    test('falseNegative divergence survives round-trip', () {
      final original = makeVerdict(engineVerdict: 'inhibited')
          .withManualVerdict(
            manualVerdict: 'applied',
            manualVerdictAtUtc: reviewTime,
            manualReviewedBy: reviewer,
          );
      final restored = ShadowVerdict.fromJson(original.toJson());
      expect(restored.divergenceType, ShadowDivergenceType.falseNegative);
    });
  });
}
