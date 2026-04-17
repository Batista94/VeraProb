/// Forensic Audit Signature: CX-05-v2.3 / FIX-4
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb Senior Engineer
library;

/// Centralized registry of binary payload signatures for forensic scanning.
///
/// Expanded from CX-05-v2.2 to include passthru, system, shell_exec (FIX-4).
class BinarySignatureRegistry {
  const BinarySignatureRegistry._();

  /// Case-insensitive regex matching PHP/script injection patterns.
  static final RegExp pattern = RegExp(
    r'<\?php|eval\s*\(|base64_decode\s*\(|passthru\s*\(|system\s*\(|shell_exec\s*\(',
    caseSensitive: false,
  );
}
