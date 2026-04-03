/// Domain exception for MFA operations.
/// INV-4: Pure Dart interface — zero infrastructure dependencies.
class MfaException implements Exception {
  final String message;
  final String? code;
  final bool isNotEnabled;

  const MfaException(this.message, {this.code, this.isNotEnabled = false});

  @override
  String toString() => message;
}
