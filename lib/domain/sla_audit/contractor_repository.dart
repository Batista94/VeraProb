import 'contractor.dart';

abstract class ContractorRepository {
  Future<List<Contractor>> findByOrganization(String organizationId);
  Future<Contractor?> findById(String organizationId, String id);
  Future<void> save(Contractor contractor);
}
