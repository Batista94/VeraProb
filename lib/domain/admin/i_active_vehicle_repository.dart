/// Domain interface for querying active vehicle availability.
///
/// Used exclusively by [DeclareContractualPlanHandler] to enforce INV-18:
/// the Engine Activation Gate requires at least one active vehicle before
/// accepting shift-based plan declarations.
///
/// Keeping this interface minimal and focused prevents coupling the handler
/// to the full vehicle management domain (Asset Manager, Bloco 8).
abstract interface class IActiveVehicleRepository {
  /// Returns the count of vehicles with status = 'active'
  /// for the given [organizationId].
  ///
  /// Returns 0 if the organization has no active vehicles or does not exist.
  Future<int> countActiveByOrganization(String organizationId);
}
