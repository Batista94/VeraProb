import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/seal_forensic_evidence_handler.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
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

/// Verifies a forensic snapshot's integrity for the given [ledgerEntryId].
///
/// Under-the-hood, it asserts the operator's tenant matches (INV-1) and
/// calls the repository verification logic.
final forensicEvidenceVerificationProvider = FutureProvider.autoDispose
    .family<EvidenceVerification, String>((ref, ledgerEntryId) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) {
        throw const DomainException('Organization context not found (INV-1)');
      }
      final repo = ref.watch(forensicEvidenceSnapshotRepositoryProvider);
      return repo.verify(organizationId: orgId, ledgerEntryId: ledgerEntryId);
    });
