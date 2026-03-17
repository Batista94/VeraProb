import 'organization.dart';

abstract class OrganizationRepository {
  Future<Organization?> findById(String id);
  Future<void> update(Organization organization);
}
