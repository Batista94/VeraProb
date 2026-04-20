/// Result DTO for contract form operations.
///
/// This class encapsulates the outcome of a contract creation/update
/// operation, allowing the UI layer to handle success and failure
/// cases without importing domain-layer exceptions (INV-4 / INV-13).
///
/// **Why this exists:** The UI must NOT import `DomainException` or
/// `SovereigntyViolationException` from `domain/`. Instead, the
/// Application layer catches those and maps them to this sealed result.
class ContractFormResult {
  /// The created contract's ID (present on success).
  final String? contractId;

  /// Human-readable error message suitable for direct UI display.
  /// Null on success.
  final String? errorMessage;

  /// Whether the operation succeeded.
  bool get isSuccess => contractId != null;

  /// Whether the operation failed.
  bool get isFailure => contractId == null;

  const ContractFormResult.success(this.contractId) : errorMessage = null;

  const ContractFormResult.failure(this.errorMessage) : contractId = null;

  /// Factory for generic/unexpected failures.
  const ContractFormResult.unknownError()
    : contractId = null,
      errorMessage = 'Erro inesperado. Tente novamente.';
}
