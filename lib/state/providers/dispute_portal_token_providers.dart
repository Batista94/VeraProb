import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/generate_dispute_portal_token_command.dart';
import 'package:veraprob/application/sla_audit/generate_dispute_portal_token_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'contract_providers.dart';

/// Per-sanction state holding the minted carrier portal token (BUG-02).
///
/// Key: queueEntryId. `AsyncData(token)` once generated, `AsyncData(null)`
/// before any generation, `AsyncLoading`/`AsyncError` mid-flight. The UI reads
/// the token to render a copyable `/portal/dispute?token=<uuid>` link.
final disputePortalTokenProvider = NotifierProvider.autoDispose
    .family<DisputePortalTokenNotifier, AsyncValue<String?>, String>(
      DisputePortalTokenNotifier.new,
    );

class DisputePortalTokenNotifier extends Notifier<AsyncValue<String?>> {
  DisputePortalTokenNotifier(this.sanctionId);
  final String sanctionId;

  @override
  AsyncValue<String?> build() => const AsyncData(null);

  GenerateDisputePortalTokenHandler get _handler =>
      GenerateDisputePortalTokenHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
        reviewRepo: ref.watch(sanctionReviewCommandRepositoryProvider),
        rbac: RbacService(),
      );

  /// Mints a portal token and exposes it via [state]. Returns the token on
  /// success (or `null` on error / disposal).
  Future<String?> generate({
    required String createdByUserId,
    required String actorEmail,
    required UserRole callerRole,
    required String organizationId,
    required String sessionId,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard<String?>(
      () => _handler.handle(
        GenerateDisputePortalTokenCommand(
          queueEntryId: sanctionId,
          createdByUserId: createdByUserId,
          actorEmail: actorEmail,
          callerRole: callerRole,
          organizationId: organizationId,
          sessionId: sessionId,
        ),
      ),
    );

    // INV-15: guard before mutating state after await.
    if (!ref.mounted) return null;

    state = result;
    return switch (result) {
      AsyncData(:final value) => value,
      _ => null,
    };
  }
}
