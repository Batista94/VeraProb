import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Value object returned by a CNPJ lookup service.
///
/// Contains the public registration information associated with a Brazilian CNPJ.
/// All fields are nullable — the lookup may return partial information depending on
/// the company's registration status.
///
/// **INV-4:** Zero infrastructure dependencies.
class CnpjCompanyData extends Equatable {
  /// The registration number. Automatically normalized to digits only.
  final String cnpj;
  final String? legalName;
  final String? tradeName;
  final String? situation; // e.g. "ATIVA", "BAIXADA", etc.

  CnpjCompanyData({
    required String cnpj,
    this.legalName,
    this.tradeName,
    this.situation,
  }) : cnpj = cnpj.replaceAll(RegExp(r'[^0-9]'), '') {
    if (this.cnpj.isEmpty) {
      throw const IntegrityException('CNPJ cannot be empty after normalisation', field: 'cnpj');
    }
  }

  factory CnpjCompanyData.fromJson(Map<String, dynamic> json) {
    return CnpjCompanyData(
      cnpj: json['cnpj']?.toString() ?? '',
      legalName: json['legal_name']?.toString() ?? json['razao_social']?.toString(),
      tradeName: json['trade_name']?.toString() ?? json['nome_fantasia']?.toString(),
      situation: json['situation']?.toString() ?? json['situacao']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'cnpj': cnpj,
        'legal_name': legalName,
        'trade_name': tradeName,
        'situation': situation,
      };

  bool get isActive => situation?.trim().toUpperCase() == 'ATIVA';

  @override
  List<Object?> get props => [cnpj, legalName, tradeName, situation];
}
