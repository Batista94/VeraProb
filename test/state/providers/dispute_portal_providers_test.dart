import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/dispute_portal/portal_submission_audit_gateway.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';

class _FakeAuditGateway implements PortalSubmissionAuditGateway {
  final List<PortalSubmissionSummary> pending;
  final List<PortalJustificationSummary> pendingJustifications;
  PortalAuditDecision? lastDecision;
  _FakeAuditGateway(this.pending, {this.pendingJustifications = const []});

  @override
  Future<List<PortalSubmissionSummary>> listPending({
    required String organizationId,
    required String queueEntryId,
  }) async => pending;

  @override
  Future<List<PortalJustificationSummary>> listPendingJustifications({
    required String organizationId,
    required String queueEntryId,
  }) async => pendingJustifications;

  @override
  Future<void> audit({
    required String organizationId,
    required String submissionId,
    required PortalAuditDecision decision,
    required String auditedByUserId,
  }) async {
    lastDecision = decision;
  }
}

PortalSubmissionSummary _summary() => const PortalSubmissionSummary(
  submissionId: 's-1',
  attachmentId: 'att-1',
  fileName: 'doc.pdf',
  mimeTypeDetected: 'application/pdf',
  fileSizeBytesActual: 2048,
  sha256Server: 'a',
  justificationText: 'Contestacao com anexo.',
  status: 'PENDING_AUDIT',
  submittedAtUtc: null,
  finalizedAtUtc: null,
);

PortalJustificationSummary _justification() => const PortalJustificationSummary(
  justificationSubmissionId: 'j-1',
  justificationText: 'Defesa textual sem anexo.',
  sha256JustificationSeal: 'b',
  status: 'PENDING_AUDIT',
  submittedAtUtc: null,
);

void main() {
  test(
    'pendingPortalSubmissionsProvider resolves via the injected gateway',
    () async {
      final c = ProviderContainer(
        overrides: [
          portalSubmissionAuditGatewayProvider.overrideWithValue(
            _FakeAuditGateway([_summary()]),
          ),
        ],
      );
      addTearDown(c.dispose);

      final rows = await c.read(
        pendingPortalSubmissionsProvider((
          orgId: 'org-1',
          queueEntryId: 'q-1',
        )).future,
      );
      expect(rows.single.submissionId, 's-1');
    },
  );

  test(
    'pendingPortalJustificationsProvider resolves via the injected gateway',
    () async {
      final c = ProviderContainer(
        overrides: [
          portalSubmissionAuditGatewayProvider.overrideWithValue(
            _FakeAuditGateway(
              const [],
              pendingJustifications: [_justification()],
            ),
          ),
        ],
      );
      addTearDown(c.dispose);

      final rows = await c.read(
        pendingPortalJustificationsProvider((
          orgId: 'org-1',
          queueEntryId: 'q-1',
        )).future,
      );
      expect(rows.single.justificationSubmissionId, 'j-1');
    },
  );

  test('portalSubmissionAuditGatewayProvider is overridable (INV-13 seam)', () {
    final fake = _FakeAuditGateway(const []);
    final c = ProviderContainer(
      overrides: [portalSubmissionAuditGatewayProvider.overrideWithValue(fake)],
    );
    addTearDown(c.dispose);
    expect(c.read(portalSubmissionAuditGatewayProvider), same(fake));
  });
}
