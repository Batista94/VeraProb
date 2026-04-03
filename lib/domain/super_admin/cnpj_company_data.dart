/// Value object returned by a CNPJ lookup service.
///
/// Contains the public registration information associated with a Brazilian CNPJ.
/// All fields are nullable — the lookup may return partial information depending on
/// the company's registration status.
///
/// **INV-4:** Zero infrastructure dependencies.
class CnpjCompanyData {
  final String cnpj;
  final String? legalName;
  final String? tradeName;
  final String? situation; // e.g. "ATIVA", "BAIXADA", etc.

  const CnpjCompanyData({
    required this.cnpj,
    this.legalName,
    this.tradeName,
    this.situation,
  });

  bool get isActive => situation?.toUpperCase() == 'ATIVA';
}
