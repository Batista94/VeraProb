/// Base for all CNPJ lookup fault conditions.
///
/// [null] return from [ICnpjLookupService.lookup] means "definitively not found".
/// A thrown [CnpjLookupException] (or subtype) means a fault occurred.
abstract class CnpjLookupException implements Exception {
  final String message;
  final String? cnpj;

  const CnpjLookupException(this.message, {this.cnpj});
}

/// CNPJ failed structural validation or Receita Federal returned status=ERROR.
///
/// These two cases are intentionally collapsed into one opaque exception to
/// prevent CNPJ enumeration oracles (INV-26).
class InvalidCnpjException extends CnpjLookupException {
  /// Internal discriminator — never surfaced to UI.
  final String reason; // 'invalid_format' | 'api_status_error'

  const InvalidCnpjException(super.message, {required this.reason, super.cnpj});

  @override
  String toString() => 'InvalidCnpjException: $message';
}

/// External API response could not be parsed or violated the declared contract.
///
/// Signals contract drift — must reach the observability layer (INV-21, INV-25).
/// Never surface raw response values in fields (INV-28).
class DataParsingException extends CnpjLookupException {
  /// The field that failed parsing, for forensic logs only.
  final String? field;

  const DataParsingException(super.message, {this.field, super.cnpj});

  @override
  String toString() =>
      'DataParsingException: $message (field: ${field ?? 'unknown'})';
}
