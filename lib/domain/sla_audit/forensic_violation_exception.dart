/// Forensic Audit Signature: CX-05-v3.0
/// Remediation: ContextualSignatureAnalyzer (two-pass verdict)
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb QA Security Lead
///
/// Thrown when binary evidence contains an embedded script payload whose
/// adjacent syntactic context confirms it as malicious code rather than
/// random binary noise (JPG/PNG entropy baseline ~37% ASCII).
library;

import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Confidence level assigned by the two-pass contextual analyzer.
///
/// - [high]: regex match AND adjacent structural-char ratio ≥ 0.60
///   (e.g. `\nshell_exec("ls"); passthru("id");\n`).
/// - [low]: regex match but structural ratio < 0.60 — treated as binary
///   noise (not raised as exception; logged silently for telemetry).
enum ForensicConfidence { high, low }

/// Thrown when binary evidence contains embedded script payloads confirmed
/// by contextual syntactic analysis.
///
/// **Forensic Guarantee (INV-9):** Evidence containing executable content is
/// quarantined before SHA-256 hashing and storage. Only [ForensicConfidence.high]
/// findings surface as exceptions; low-confidence matches are logged and
/// sampling continues to reduce false-positive pressure on legitimate media.
class ForensicViolationException extends DomainException {
  /// The storage URL of the offending evidence file.
  final String evidenceUrl;

  /// Confidence of the forensic verdict (see [ForensicConfidence]).
  final ForensicConfidence confidence;

  const ForensicViolationException({
    required String message,
    required this.evidenceUrl,
    this.confidence = ForensicConfidence.high,
  }) : super(message);
}
