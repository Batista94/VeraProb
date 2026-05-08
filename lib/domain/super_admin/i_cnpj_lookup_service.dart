import 'cnpj_company_data.dart';
import 'cnpj_exceptions.dart';

/// Domain interface for CNPJ lookup / enrichment.
///
/// Returns `null` when the registry definitively has no record (not found /
/// cancelled). Throws [CnpjLookupException] or a subtype for all fault
/// conditions. Throws [InvalidCnpjException] if [cnpjDigits] fails structural
/// validation before reaching the registry.
///
/// **INV-4:** Interface lives in domain; implementation in infrastructure.
/// **INV-25:** Implementation must use a free/freemium service.
/// **INV-26:** All fault paths must be indistinguishable to callers — never
/// reveal whether a CNPJ "exists" vs "was rejected" via exception type.
abstract class ICnpjLookupService {
  Future<CnpjCompanyData?> lookup(String cnpjDigits);
}
