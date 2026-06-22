// Unit: PortalDisputeSubmissionNotifier retry orchestration (PKG2).
//
// Only retryable (infra 503) failures are retried with backoff; business
// rejections (INV-26) fail immediately. A retried submit re-invokes the gateway
// end-to-end (idempotency at the DB makes that safe — migration 20260825000001).
// Backoff is collapsed to zero via PortalRetryPolicy.zeroDelay for determinism.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_submission_notifier.dart';
import 'package:veraprob/application/dispute_portal/portal_retry_policy.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';

class _RetryFakeGateway implements PortalDisputeGateway {
  final int failuresBeforeSuccess;
  final bool retryable;
  int submitCalls = 0;

  _RetryFakeGateway({this.failuresBeforeSuccess = 0, this.retryable = true});

  @override
  Future<PortalSubmissionOutcome> submitEvidence({
    required String token,
    required String justification,
    StagedFile? file,
    required String? sha256Client,
  }) async {
    submitCalls++;
    if (submitCalls <= failuresBeforeSuccess) {
      throw PortalDisputeException('infra down', retryable: retryable);
    }
    return PortalSubmissionOutcome.pendingAudit;
  }

  @override
  Future<PortalSnapshot> read(String token) => throw UnimplementedError();

  @override
  Future<InfractionContextProjection> readInfractionContext(String token) =>
      throw UnimplementedError();

  @override
  Future<void> acknowledge({
    required String token,
    required String snapshotHash,
  }) => throw UnimplementedError();
}

void main() {
  const justification = 'Justificativa longa o suficiente para passar.';

  ({ProviderContainer container, List<PortalSubmissionState> states}) harness(
    _RetryFakeGateway gateway,
  ) {
    final container = ProviderContainer(
      overrides: [
        portalDisputeGatewayProvider.overrideWithValue(gateway),
        portalRetryPolicyProvider.overrideWithValue(
          PortalRetryPolicy.zeroDelay,
        ),
      ],
    );
    addTearDown(container.dispose);
    final states = <PortalSubmissionState>[];
    container.listen<PortalSubmissionState>(
      portalDisputeSubmissionNotifierProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    return (container: container, states: states);
  }

  test('retryable failures then success → PortalSubmissionSuccess', () async {
    final gateway = _RetryFakeGateway(failuresBeforeSuccess: 2);
    final h = harness(gateway);
    final notifier = h.container.read(
      portalDisputeSubmissionNotifierProvider.notifier,
    );

    notifier.setJustification(justification);
    await notifier.submit('tok');

    expect(gateway.submitCalls, 3); // default maxAttempts
    expect(
      h.container.read(portalDisputeSubmissionNotifierProvider),
      isA<PortalSubmissionSuccess>(),
    );
    expect(
      h.states.whereType<PortalSubmissionRetrying>().length,
      2,
      reason: 'two retries surfaced before the success',
    );
  });

  test(
    'retryable failures exhaust maxAttempts → PortalSubmissionError (retryable cause)',
    () async {
      final gateway = _RetryFakeGateway(failuresBeforeSuccess: 99);
      final h = harness(gateway);
      final notifier = h.container.read(
        portalDisputeSubmissionNotifierProvider.notifier,
      );

      notifier.setJustification(justification);
      await notifier.submit('tok');

      expect(gateway.submitCalls, 3);
      final state = h.container.read(portalDisputeSubmissionNotifierProvider);
      expect(state, isA<PortalSubmissionError>());
      final cause = (state as PortalSubmissionError).cause;
      expect(cause, isA<PortalDisputeException>());
      expect((cause as PortalDisputeException).retryable, isTrue);
      // Justification preserved so the carrier can re-submit manually.
      expect(state.recoverable.justification, justification);
    },
  );

  test('non-retryable rejection → PortalSubmissionError, no retry', () async {
    final gateway = _RetryFakeGateway(
      failuresBeforeSuccess: 1,
      retryable: false,
    );
    final h = harness(gateway);
    final notifier = h.container.read(
      portalDisputeSubmissionNotifierProvider.notifier,
    );

    notifier.setJustification(justification);
    await notifier.submit('tok');

    expect(gateway.submitCalls, 1);
    expect(
      h.container.read(portalDisputeSubmissionNotifierProvider),
      isA<PortalSubmissionError>(),
    );
    expect(h.states.whereType<PortalSubmissionRetrying>(), isEmpty);
  });
}
