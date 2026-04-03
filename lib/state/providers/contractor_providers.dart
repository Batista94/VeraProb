import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_client.dart';
import '../../application/sla_audit/projections/contractor_view.dart';
import '../../domain/sla_audit/contractor_repository.dart';
import '../../infrastructure/sla_audit/postgres_contractor_repository.dart';
import '../../application/sla_audit/save_contractor_handler.dart';
import '../../application/sla_audit/delete_contractor_handler.dart';
import 'auth_providers.dart';

/// Provider for the contractor repository implementation.
final contractorRepositoryProvider = Provider<ContractorRepository>((ref) {
  return PostgresContractorRepository(supabase);
});

/// Future provider for the list of contractors in the current organization.
final contractorListProvider = FutureProvider<List<ContractorView>>((
  ref,
) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return [];
  final contractors =
      await ref.watch(contractorRepositoryProvider).findByOrganization(orgId);
  return contractors.map(ContractorView.fromDomain).toList();
});

/// Provider for the save contractor handler.
final saveContractorHandlerProvider = Provider<SaveContractorHandler>((ref) {
  return SaveContractorHandler(
    repository: ref.watch(contractorRepositoryProvider),
  );
});

/// Provider for the delete contractor handler.
final deleteContractorHandlerProvider = Provider<DeleteContractorHandler>((
  ref,
) {
  return DeleteContractorHandler(
    repository: ref.watch(contractorRepositoryProvider),
  );
});
