import 'dart:typed_data';

import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';

/// Port (INV-13) for the external, tokenized dispute portal. Implemented in
/// infrastructure over the anon Supabase client + the two portal edge functions.
///
/// Presentation depends ONLY on this abstraction, never on Supabase directly.
abstract class PortalDisputeGateway {
  /// Reads the sealed dispute snapshot for [token]. Throws
  /// [PortalDisputeException] on an invalid/expired/revoked token (404 parity).
  Future<PortalSnapshot> read(String token);

  /// Records the carrier "De Acordo" for the served [snapshotHash]. Throws
  /// [PortalDisputeException] if the hash was not the one served (INV-9) or the
  /// sanction is not applied.
  Future<void> acknowledge({
    required String token,
    required String snapshotHash,
  });

  /// Submits one counter-evidence file: requests a signed upload URL, PUTs the
  /// bytes to quarantine, then finalizes (server-side magic-byte + SHA-256
  /// verification, INV-9). Returns the verification outcome.
  Future<PortalSubmissionOutcome> submitEvidence({
    required String token,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  });
}
