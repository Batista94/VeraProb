import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/application/admin/import_csv_handler.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/features/admin/presentation/utils/csv_target_field_labels.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/session_recovery.dart';

// ── Sealed state ──────────────────────────────────────────────────────────────

sealed class CsvImportFlowState {
  const CsvImportFlowState({
    required this.currentStep,
    required this.targetEntity,
  });
  final int currentStep;
  final String targetEntity;
}

class CsvImportInitial extends CsvImportFlowState {
  const CsvImportInitial({required super.targetEntity}) : super(currentStep: 0);
}

class CsvImportFileLoaded extends CsvImportFlowState {
  const CsvImportFileLoaded({
    required super.targetEntity,
    required this.fileName,
    required this.headers,
    required this.previewRows,
    required this.allRows,
    required this.rawBytes,
  }) : super(currentStep: 1);

  final String fileName;
  final List<String> headers;
  final List<Map<String, String>> previewRows;
  final List<Map<String, String>> allRows;
  final List<int> rawBytes;
}

class CsvImportMapped extends CsvImportFileLoaded {
  const CsvImportMapped({
    required super.targetEntity,
    required super.fileName,
    required super.headers,
    required super.previewRows,
    required super.allRows,
    required super.rawBytes,
    required this.mappings,
    this.selectedTemplateId,
    this.saveAsTemplate = false,
    this.templateName = '',
  });

  final Map<String, ColumnMapping?> mappings;
  final String? selectedTemplateId;
  final bool saveAsTemplate;
  final String templateName;

  CsvImportMapped copyWithMapping({
    Map<String, ColumnMapping?>? mappings,
    String? selectedTemplateId,
    bool clearTemplateId = false,
    bool? saveAsTemplate,
    String? templateName,
  }) {
    return CsvImportMapped(
      targetEntity: targetEntity,
      fileName: fileName,
      headers: headers,
      previewRows: previewRows,
      allRows: allRows,
      rawBytes: rawBytes,
      mappings: mappings ?? this.mappings,
      selectedTemplateId: clearTemplateId
          ? null
          : (selectedTemplateId ?? this.selectedTemplateId),
      saveAsTemplate: saveAsTemplate ?? this.saveAsTemplate,
      templateName: templateName ?? this.templateName,
    );
  }
}

class CsvImportValidated extends CsvImportMapped {
  const CsvImportValidated({
    required super.targetEntity,
    required super.fileName,
    required super.headers,
    required super.previewRows,
    required super.allRows,
    required super.rawBytes,
    required super.mappings,
    super.selectedTemplateId,
    super.saveAsTemplate,
    super.templateName,
    required this.report,
  });

  @override
  int get currentStep => 2;

  final CsvPreflightReport report;
}

class CsvImportSubmitting extends CsvImportValidated {
  const CsvImportSubmitting({
    required super.targetEntity,
    required super.fileName,
    required super.headers,
    required super.previewRows,
    required super.allRows,
    required super.rawBytes,
    required super.mappings,
    super.selectedTemplateId,
    super.saveAsTemplate,
    super.templateName,
    required super.report,
  });
}

class CsvImportDone extends CsvImportFlowState {
  const CsvImportDone({required super.targetEntity, required this.result})
    : super(currentStep: 3);

  final CsvImportResult result;
}

class CsvImportError extends CsvImportFlowState {
  const CsvImportError({
    required super.targetEntity,
    required super.currentStep,
    required this.message,
    this.previousState,
  });

  final String message;
  final CsvImportFlowState? previousState;
}

// ── Templates provider ────────────────────────────────────────────────────────

final csvTemplatesProvider = FutureProvider.autoDispose
    .family<List<CsvMappingTemplate>, String>((ref, targetEntity) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return const [];
      final repo = ref.watch(csvMappingTemplateRepositoryProvider);
      return repo.getTemplates(
        organizationId: orgId,
        targetEntity: targetEntity,
      );
    });

// ── Flow Notifier ─────────────────────────────────────────────────────────────

class CsvImportFlowNotifier extends Notifier<CsvImportFlowState> {
  @override
  CsvImportFlowState build() =>
      const CsvImportInitial(targetEntity: 'operator');

  String get _targetEntity => state.targetEntity;

  void setEntity(String entity) {
    state = CsvImportInitial(targetEntity: entity);
  }

  /// Called when dialog opens with a pre-set entity.
  void init(String entity) {
    state = CsvImportInitial(targetEntity: entity);
  }

  Future<void> pickFile() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'tsv'],
        withData: true,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        print('[CSV Import Picker Error] $e\n$stack');
      }
      _setError(
        'Não foi possível abrir o seletor de arquivos. Tente novamente.',
      );
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _setError('Não foi possível ler o arquivo selecionado.');
      return;
    }

    final ext = (file.extension ?? '').toLowerCase();
    if (ext != 'csv' && ext != 'tsv') {
      _setError('Formato inválido. Use .csv ou .tsv.');
      return;
    }

    try {
      final csvString = utf8.decode(bytes);
      final rawRows = Csv(
        lineDelimiter: '\n',
        dynamicTyping: false,
      ).decode(csvString);

      if (rawRows.isEmpty) {
        _setError('Arquivo CSV vazio.');
        return;
      }

      final headers = rawRows.first
          .map((Object? e) => (e ?? '').toString().trim())
          .where((h) => h.isNotEmpty)
          .toList();

      if (headers.isEmpty) {
        _setError('Nenhuma coluna encontrada no arquivo.');
        return;
      }

      final dataRows = rawRows.skip(1).map((row) {
        final map = <String, String>{};
        for (var j = 0; j < headers.length; j++) {
          map[headers[j]] = j < row.length ? row[j].toString() : '';
        }
        return map;
      }).toList();

      final previewRows = dataRows.take(3).toList();

      // Bloco 1B: auto-match headers to target fields.
      // Pre-fills mappings so the user needs minimal manual intervention.
      final autoMappings = _autoMatch(headers: headers, entity: _targetEntity);

      state = CsvImportMapped(
        targetEntity: _targetEntity,
        fileName: file.name,
        headers: headers,
        previewRows: previewRows,
        allRows: dataRows,
        rawBytes: bytes.toList(),
        mappings: autoMappings,
      );
    } on FormatException catch (e, stack) {
      if (kDebugMode) {
        print('[CSV Import Decodification Error] $e\n$stack');
      }
      _setError('Arquivo não pôde ser decodificado como UTF-8.');
    } catch (e, stack) {
      if (kDebugMode) {
        print('[CSV Import Processing Error] $e\n$stack');
      }
      _setError('Erro ao processar o arquivo CSV.');
    }
  }

  void applyTemplate(CsvMappingTemplate template) {
    var current = state;
    if (current is CsvImportError && current.previousState != null) {
      current = current.previousState!;
    }
    if (current is! CsvImportMapped) return;

    final newMappings = Map<String, ColumnMapping?>.from(current.mappings);
    for (final cm in template.columnMappings) {
      if (newMappings.containsKey(cm.csvHeader)) {
        newMappings[cm.csvHeader] = cm;
      }
    }
    state = current.copyWithMapping(
      mappings: newMappings,
      selectedTemplateId: template.id,
    );
  }

  void updateMapping(
    String csvHeader,
    CsvTargetField? targetField,
    String? transform,
  ) {
    var current = state;
    if (current is CsvImportError && current.previousState != null) {
      current = current.previousState!;
    }
    if (current is! CsvImportMapped) return;

    final newMappings = Map<String, ColumnMapping?>.from(current.mappings);
    if (targetField == null) {
      newMappings[csvHeader] = null;
    } else {
      newMappings[csvHeader] = ColumnMapping(
        csvHeader: csvHeader,
        targetField: targetField,
        transform: transform,
      );
    }
    state = current.copyWithMapping(
      mappings: newMappings,
      clearTemplateId: current.selectedTemplateId != null,
    );
  }

  void toggleSaveTemplate(bool value) {
    var current = state;
    if (current is CsvImportError && current.previousState != null) {
      current = current.previousState!;
    }
    if (current is! CsvImportMapped) return;
    state = current.copyWithMapping(saveAsTemplate: value);
  }

  void setTemplateName(String name) {
    var current = state;
    if (current is CsvImportError && current.previousState != null) {
      current = current.previousState!;
    }
    if (current is! CsvImportMapped) return;
    state = current.copyWithMapping(templateName: name);
  }

  /// Active mappings with [ColumnMapping.required] set for every field the
  /// target entity needs (NOT-NULL DB columns). Lets the preflight reject a
  /// blank required cell per-row, in addition to the unmapped-column gate.
  List<ColumnMapping> _activeMappings(
    Map<String, ColumnMapping?> mappings,
    String entity,
  ) {
    final required = CsvTargetField.requiredForEntity(entity).toSet();
    return mappings.values.whereType<ColumnMapping>().map((m) {
      if (!required.contains(m.targetField) || m.required) return m;
      return ColumnMapping(
        csvHeader: m.csvHeader,
        targetField: m.targetField,
        transform: m.transform,
        required: true,
        formatHint: m.formatHint,
      );
    }).toList();
  }

  Future<void> validate() async {
    var current = state;
    if (current is CsvImportError && current.previousState != null) {
      current = current.previousState!;
    }
    if (current is! CsvImportMapped) return;

    final activeMappings = _activeMappings(
      current.mappings,
      current.targetEntity,
    );

    if (activeMappings.isEmpty) {
      _setError('Mapeie ao menos uma coluna antes de validar.');
      return;
    }

    // Resilient session recovery: attempt token refresh before giving up
    final orgId = await SessionRecovery.ensureOrgId(ref);
    if (orgId == null) {
      _setError('Sessão expirada. Faça login novamente.');
      return;
    }

    final template = CsvMappingTemplate(
      id: current.selectedTemplateId ?? '',
      organizationId: orgId,
      name: current.templateName.isNotEmpty ? current.templateName : 'AdHoc',
      targetEntity: current.targetEntity,
      columnMappings: activeMappings,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    final validator = ref.read(csvPreflightValidatorProvider);
    final rowReport = validator.validate(current.allRows, template);
    final report = _withCoverage(rowReport, validator, template);

    state = CsvImportValidated(
      targetEntity: current.targetEntity,
      fileName: current.fileName,
      headers: current.headers,
      previewRows: current.previewRows,
      allRows: current.allRows,
      rawBytes: current.rawBytes,
      mappings: current.mappings,
      selectedTemplateId: current.selectedTemplateId,
      saveAsTemplate: current.saveAsTemplate,
      templateName: current.templateName,
      report: report,
    );
  }

  /// Merges the mapping-coverage gate into the row-level [rowReport]: a required
  /// NOT-NULL field with no column mapping makes EVERY row invalid, so we force
  /// `validRows: 0` and surface a blocking error per missing field. The Import
  /// CTA is gated on `validRows > 0`, so this stops the import before the RPC
  /// raises a 23502 null-value violation (INV-10 fail-fast).
  CsvPreflightReport _withCoverage(
    CsvPreflightReport rowReport,
    CsvPreflightValidator validator,
    CsvMappingTemplate template,
  ) {
    final unmapped = validator.findUnmappedRequired(template);
    if (unmapped.isEmpty) return rowReport;
    return CsvPreflightReport(
      totalRows: rowReport.totalRows,
      validRows: 0,
      errors: [
        for (final field in unmapped)
          CsvRowError(
            rowIndex: 0,
            csvHeader: '—',
            targetField: field.dbValue,
            errorCode: 'unmapped_required',
            message:
                'Coluna obrigatória "${csvTargetFieldLabel(field)}" não foi '
                'mapeada a nenhuma coluna do CSV.',
          ),
        ...rowReport.errors,
      ],
    );
  }

  Future<void> submit() async {
    var current = state;
    if (current is CsvImportError && current.previousState != null) {
      current = current.previousState!;
    }
    if (current is! CsvImportValidated) return;

    // Resilient session recovery: attempt token refresh before giving up
    final session = await SessionRecovery.ensureSession(ref);
    if (session == null) {
      _setError('Sessão expirada. Faça login novamente.');
      return;
    }

    state = CsvImportSubmitting(
      targetEntity: current.targetEntity,
      fileName: current.fileName,
      headers: current.headers,
      previewRows: current.previewRows,
      allRows: current.allRows,
      rawBytes: current.rawBytes,
      mappings: current.mappings,
      selectedTemplateId: current.selectedTemplateId,
      saveAsTemplate: current.saveAsTemplate,
      templateName: current.templateName,
      report: current.report,
    );

    try {
      final activeMappings = _activeMappings(
        current.mappings,
        current.targetEntity,
      );

      final command = ImportCsvCommand(
        sessionId: session.sessionId,
        organizationId: session.orgId,
        targetEntity: current.targetEntity,
        templateId: current.selectedTemplateId,
        rawBytes: current.rawBytes,
        adhocMappings: current.selectedTemplateId == null
            ? activeMappings
            : null,
      );

      final handler = ref.read(importCsvHandlerProvider);
      final result = await handler.handle(command);

      state = CsvImportDone(targetEntity: current.targetEntity, result: result);
    } on SovereigntyViolationException {
      _setError(
        'Sessão expirada ou inválida. Por favor, faça login novamente.',
        current,
      );
    } on IntegrityException catch (e) {
      _setError(e.message, current);
    } catch (e, stack) {
      if (kDebugMode) {
        print('[CSV Import Submission Error] $e\n$stack');
      }
      _setError(
        'Falha ao importar. Verifique sua conexão e tente novamente.',
        current,
      );
    }
  }

  void goBack() {
    var current = state;
    if (current is CsvImportError && current.previousState != null) {
      current = current.previousState!;
    }
    switch (current) {
      case CsvImportValidated():
        state = CsvImportMapped(
          targetEntity: current.targetEntity,
          fileName: current.fileName,
          headers: current.headers,
          previewRows: current.previewRows,
          allRows: current.allRows,
          rawBytes: current.rawBytes,
          mappings: current.mappings,
          selectedTemplateId: current.selectedTemplateId,
          saveAsTemplate: current.saveAsTemplate,
          templateName: current.templateName,
        );
      case CsvImportMapped():
        state = CsvImportInitial(targetEntity: current.targetEntity);
      default:
        break;
    }
  }

  void reset() {
    state = CsvImportInitial(targetEntity: _targetEntity);
  }

  void _setError(String message, [CsvImportFlowState? previousState]) {
    final previousNonErrorState =
        previousState ??
        (state is CsvImportError
            ? (state as CsvImportError).previousState
            : state);
    state = CsvImportError(
      targetEntity: _targetEntity,
      currentStep: state.currentStep,
      message: message,
      previousState: previousNonErrorState,
    );
  }

  // ── Auto-Match (Bloco 1B) ────────────────────────────────────────────────

  /// Lexical auto-match: maps CSV headers to [CsvTargetField] using
  /// normalised string comparison (lowercase, strip non-alphanumeric).
  ///
  /// Entity-scoped: a pattern matching [CsvTargetField.latitude] will produce
  /// `null` if `entity == 'contractor'` because latitude is not whitelisted.
  Map<String, ColumnMapping?> _autoMatch({
    required List<String> headers,
    required String entity,
  }) {
    final scopedFields = CsvTargetField.forEntity(entity);
    final result = <String, ColumnMapping?>{};
    for (final header in headers) {
      final normalized = _normalizeHeader(header);
      final match = _kAutoMatchRules.firstWhereOrNull(
        (rule) =>
            rule.$1.hasMatch(normalized) && scopedFields.contains(rule.$2),
      );
      result[header] = match == null
          ? null
          : ColumnMapping(csvHeader: header, targetField: match.$2);
    }
    return result;
  }

  /// Exposes [_autoMatch] for unit testing without breaking encapsulation.
  @visibleForTesting
  Map<String, ColumnMapping?> autoMatchForTest({
    required List<String> headers,
    required String entity,
  }) => _autoMatch(headers: headers, entity: entity);

  /// Normalises a CSV header for fuzzy matching:
  /// lowercases and strips all non-alphanumeric characters.
  static String _normalizeHeader(String h) =>
      h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Priority-ordered match rules: (pattern, field).
  ///
  /// IMPORTANT: evaluated in declaration order — more specific rules first.
  static final List<(RegExp, CsvTargetField)> _kAutoMatchRules = [
    // ── externalId (highest priority — integration anchor) ────────────────
    (
      RegExp(r'^(idexterno|externalid|ext_id|extid|chaveintegracao)$'),
      CsvTargetField.externalId,
    ),

    // ── contractor document ────────────────────────────────────────────────
    (
      RegExp(
        r'^(cnpj|cnpjcliente|cnpjcontratante|taxid|documentocontratante|documento|doc|contractordocument)$',
      ),
      CsvTargetField.contractorDocument,
    ),

    // ── operator document (CPF — 11 digits) ───────────────────────────────
    // 'documento'/'doc' appears above for contractorDocument; for operator
    // entities the entity scope guard ensures contractorDocument is not
    // in scopedFields, so the firstWhereOrNull continues to this rule.
    (
      RegExp(r'^(cpf|documentooperador|documentomotorista|documento|doc)$'),
      CsvTargetField.operatorDocument,
    ),

    // ── asset identifier ───────────────────────────────────────────────────
    (
      RegExp(r'^(placa|plate|identificador|serial|chassi|frota)$'),
      CsvTargetField.identifier,
    ),

    // ── operator fields ────────────────────────────────────────────────────
    (
      RegExp(r'^(nome|name|nomecompleto|nomeoperador|razaosocial)$'),
      CsvTargetField.operatorName,
    ),
    (
      RegExp(r'^(habilitacao|cnh|licensenumber|license|carteira)$'),
      CsvTargetField.operatorLicense,
    ),
    (
      RegExp(r'^(telefone|phone|celular|contato|cel)$'),
      CsvTargetField.operatorPhone,
    ),

    // ── contractor fields (Bloco 1C.0) ─────────────────────────────────────
    // Scope guard keeps these from colliding with operator/zone name rules:
    // contractorName is only in scope for entity 'contractor'.
    (
      RegExp(
        r'^(nomecontratante|razaosocial|nomefantasia|nome|name|contractorname)$',
      ),
      CsvTargetField.contractorName,
    ),
    (
      RegExp(
        r'^(email|emailcontratante|emailprincipal|emailcontato|contractoremail)$',
      ),
      CsvTargetField.contractorEmail,
    ),
    (
      RegExp(
        r'^(contato|responsavel|nomecontato|pessoacontato|contractorcontactname)$',
      ),
      CsvTargetField.contractorContactName,
    ),

    // ── asset fields ───────────────────────────────────────────────────────
    (RegExp(r'^(modelo|model|marca)$'), CsvTargetField.assetModel),
    (
      RegExp(r'^(capacidade|capacity|lugares|assentos|seats)$'),
      CsvTargetField.capacity,
    ),
    (RegExp(r'^(status|situacao|estado)$'), CsvTargetField.assetStatus),

    // ── contract fields ────────────────────────────────────────────────────
    (
      RegExp(r'^(codigocontrato|contractcode|contrato|numcontrato)$'),
      CsvTargetField.contractCode,
    ),
    (
      RegExp(r'^(datainicio|startdate|inicio|start|vigenciainicio)$'),
      CsvTargetField.startDate,
    ),
    (
      RegExp(r'^(datafim|enddate|fim|end|vigenciafim|termino)$'),
      CsvTargetField.endDate,
    ),

    // ── zone fields ───────────────────────────────────────────────────────
    (RegExp(r'^(nomezona|zonename|zona|nome)$'), CsvTargetField.zoneName),
    (
      RegExp(r'^(codigozona|zonecode|codigoexterno|codigo)$'),
      CsvTargetField.zoneCode,
    ),
    (RegExp(r'^(lat|latitude)$'), CsvTargetField.latitude),
    (RegExp(r'^(lon|lng|longitude)$'), CsvTargetField.longitude),
    (
      RegExp(r'^(raio|radius|radiometros|radiusmeters)$'),
      CsvTargetField.radiusMeters,
    ),

    // ── notes ─────────────────────────────────────────────────────────────
    (
      RegExp(r'^(observacoes|notes|obs|nota|observacao)$'),
      CsvTargetField.notes,
    ),
  ];
}

final csvImportFlowProvider =
    NotifierProvider.autoDispose<CsvImportFlowNotifier, CsvImportFlowState>(
      CsvImportFlowNotifier.new,
    );

extension CsvImportFlowStateX on CsvImportFlowState {
  CsvImportFlowState get activeState {
    final self = this;
    if (self is CsvImportError && self.previousState != null) {
      return self.previousState!;
    }
    return self;
  }
}
