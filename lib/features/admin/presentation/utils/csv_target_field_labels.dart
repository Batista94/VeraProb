import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore

/// PT-BR labels for CsvTargetField values (INV-14: domain stays agnostic).
const Map<CsvTargetField, String> _kFieldLabels = {
  CsvTargetField.identifier: 'Identificador (Placa/Serial)',
  CsvTargetField.assetModel: 'Modelo do Ativo',
  CsvTargetField.capacity: 'Capacidade (Lugares)',
  CsvTargetField.assetStatus: 'Status do Ativo',
  CsvTargetField.operatorName: 'Nome do Operador',
  CsvTargetField.operatorDocument: 'CPF do Operador',
  CsvTargetField.operatorLicense: 'Número da CNH',
  CsvTargetField.operatorLicenseCategory: 'Categoria da CNH',
  CsvTargetField.operatorLicenseExpiry: 'Validade da CNH',
  CsvTargetField.operatorPhone: 'Telefone de Contato',
  CsvTargetField.contractorName: 'Razão Social do Contratante',
  CsvTargetField.contractorEmail: 'E-mail do Contratante',
  CsvTargetField.contractorContactName: 'Nome do Contato',
  CsvTargetField.contractCode: 'Código do Contrato',
  CsvTargetField.contractorDocument: 'CNPJ do Contratante',
  CsvTargetField.startDate: 'Data de Início',
  CsvTargetField.endDate: 'Data de Término',
  CsvTargetField.zoneName: 'Nome da Zona',
  CsvTargetField.zoneCode: 'Código Externo da Zona',
  CsvTargetField.latitude: 'Latitude da Zona',
  CsvTargetField.longitude: 'Longitude da Zona',
  CsvTargetField.radiusMeters: 'Distância de Detecção (metros)',
  CsvTargetField.externalId: 'ID Externo (Deduplicação)',
  CsvTargetField.notes: 'Observações',
};

String csvTargetFieldLabel(CsvTargetField field) =>
    _kFieldLabels[field] ?? field.name;
