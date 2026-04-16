/// Forensic Audit Signature: CX-05-v2.1
/// Remediation: Red Team v2.2 — Fix 4 (Binary Sampling Gap)
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb QA Security Lead
///
/// Thrown when binary evidence contains an embedded script payload detected
/// during random-chunk sampling of the file body (not just Magic Bytes header).
library;

import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Thrown when binary evidence contains embedded script payloads.
///
/// Raised by [EvidenceBinaryValidator._scanForScriptPayloads] when any
/// sampled probe (head / mid / tail) contains `<?php`, `<script`, or `eval(`.
///
/// **Forensic Guarantee (INV-9):** Evidence containing executable content
/// is quarantined before SHA-256 hashing and storage. The violation is logged
/// with the offending URL so the incident can be traced.
class ForensicViolationException extends DomainException {
  /// The storage URL of the offending evidence file.
  final String evidenceUrl;

  const ForensicViolationException({
    required String message,
    required this.evidenceUrl,
  }) : super(message);
}
