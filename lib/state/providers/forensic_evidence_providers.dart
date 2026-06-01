import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/seal_forensic_evidence_handler.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'contract_providers.dart';

/// Application handler that seals verdicts into the Forensic Evidence Vault.
final sealForensicEvidenceHandlerProvider =
    Provider<SealForensicEvidenceHandler>((ref) {
      return SealForensicEvidenceHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        vault: ref.watch(forensicEvidenceSnapshotRepositoryProvider),
      );
    });
