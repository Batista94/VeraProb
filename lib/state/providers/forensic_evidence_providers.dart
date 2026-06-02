import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/evidence_snapshot_view.dart';
import 'package:veraprob/application/sla_audit/seal_forensic_evidence_handler.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'auth_providers.dart';
import 'contract_providers.dart';

/// Application handler that seals verdicts into the Forensic Evidence Vault.
final sealForensicEvidenceHandlerProvider =
    Provider<SealForensicEvidenceHandler>((ref) {
      return SealForensicEvidenceHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        vault: ref.watch(forensicEvidenceSnapshotRepositoryProvider),
      );
    });

/// Verifies a forensic snapshot's integrity for [ledgerEntryId].
/// Returns [EvidenceSnapshotView.tampered] on [IntegrityException] so the
/// presentation layer never imports domain exception types (INV-13).
final forensicEvidenceVerificationProvider = FutureProvider.autoDispose
    .family<EvidenceSnapshotView, String>((ref, ledgerEntryId) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) {
        throw const DomainException('Organization context not found (INV-1)');
      }
      final repo = ref.watch(forensicEvidenceSnapshotRepositoryProvider);
      try {
        final result = await repo.verify(
          organizationId: orgId,
          ledgerEntryId: ledgerEntryId,
        );
        return EvidenceSnapshotView.fromVerification(result);
      } on IntegrityException {
        return EvidenceSnapshotView.tampered(ledgerEntryId);
      }
    });
