import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';

class _FakeGateway implements PortalDisputeGateway {
  final PortalSnapshot? snapshot;
  final PortalSubmissionOutcome outcome;
  String? acknowledgedHash;

  _FakeGateway({
    this.snapshot,
    this.outcome = PortalSubmissionOutcome.pendingAudit,
  });

  @override
  Future<PortalSnapshot> read(String token) async {
    final s = snapshot;
    if (s == null) {
      throw const PortalDisputeException('Link inválido ou expirado.');
    }
    return s;
  }

  @override
  Future<void> acknowledge({
    required String token,
    required String snapshotHash,
  }) async {
    acknowledgedHash = snapshotHash;
  }

  @override
  Future<InfractionContextProjection> readInfractionContext(
    String token,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PortalSubmissionOutcome> submitEvidence({
    required String token,
    required String justification,
    StagedFile? file,
    required String? sha256Client,
  }) async {
    return outcome;
  }
}

PortalSnapshot _snap(String status) => PortalSnapshot(
  status: status,
  disputedAtUtc: null,
  resolutionDueAtUtc: null,
  ruleType: 'Atraso',
  description: null,
  evidence: const [],
  snapshotHash: 'a' * 64,
);

void main() {
  group('PortalDisputeGateway (port contract)', () {
    test('read returns the served snapshot', () async {
      final g = _FakeGateway(snapshot: _snap('applied'));
      final s = await g.read('tok');
      expect(s.isApplied, isTrue);
    });

    test(
      'read maps an invalid token to PortalDisputeException (404 parity)',
      () {
        final g = _FakeGateway();
        expect(() => g.read('tok'), throwsA(isA<PortalDisputeException>()));
      },
    );

    test('acknowledge echoes the snapshot hash bound by the caller', () async {
      final g = _FakeGateway(snapshot: _snap('applied'));
      await g.acknowledge(token: 'tok', snapshotHash: 'a' * 64);
      expect(g.acknowledgedHash, 'a' * 64);
    });

    test('submitEvidence returns the verification outcome', () async {
      final g = _FakeGateway(outcome: PortalSubmissionOutcome.mimeMismatch);
      final o = await g.submitEvidence(
        token: 'tok',
        justification: 'justificativa',
        sha256Client: 'a' * 64,
      );
      expect(o, PortalSubmissionOutcome.mimeMismatch);
    });
  });
}
