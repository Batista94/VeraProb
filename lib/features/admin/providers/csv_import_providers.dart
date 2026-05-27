import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/application/admin/import_csv_handler.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

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
  });

  final String message;
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'tsv'],
      withData: true,
    );
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

      final emptyMappings = <String, ColumnMapping?>{
        for (final h in headers) h: null,
      };

      state = CsvImportMapped(
        targetEntity: _targetEntity,
        fileName: file.name,
        headers: headers,
        previewRows: previewRows,
        allRows: dataRows,
        rawBytes: bytes.toList(),
        mappings: emptyMappings,
      );
    } on FormatException {
      _setError('Arquivo não pôde ser decodificado como UTF-8.');
    } catch (_) {
      _setError('Erro ao processar o arquivo CSV.');
    }
  }

  void applyTemplate(CsvMappingTemplate template) {
    final current = state;
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
    final current = state;
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
    final current = state;
    if (current is! CsvImportMapped) return;
    state = current.copyWithMapping(saveAsTemplate: value);
  }

  void setTemplateName(String name) {
    final current = state;
    if (current is! CsvImportMapped) return;
    state = current.copyWithMapping(templateName: name);
  }

  void validate() {
    final current = state;
    if (current is! CsvImportMapped) return;

    final activeMappings = current.mappings.values
        .whereType<ColumnMapping>()
        .toList();

    if (activeMappings.isEmpty) {
      _setError('Mapeie ao menos uma coluna antes de validar.');
      return;
    }

    final orgId = ref.read(currentOrganizationIdProvider);
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
    final report = validator.validate(current.allRows, template);

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

  Future<void> submit() async {
    final current = state;
    if (current is! CsvImportValidated) return;

    final orgId = ref.read(currentOrganizationIdProvider);
    final sessionId = ref.read(currentSessionIdProvider);
    if (orgId == null || sessionId == null) {
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
      final activeMappings = current.mappings.values
          .whereType<ColumnMapping>()
          .toList();

      final command = ImportCsvCommand(
        sessionId: sessionId,
        organizationId: orgId,
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
    } on IntegrityException catch (e) {
      _setError(e.message);
    } catch (_) {
      _setError('Falha ao importar. Verifique sua conexão e tente novamente.');
    }
  }

  void goBack() {
    final current = state;
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

  void _setError(String message) {
    state = CsvImportError(
      targetEntity: _targetEntity,
      currentStep: state.currentStep,
      message: message,
    );
  }
}

final csvImportFlowProvider =
    NotifierProvider.autoDispose<CsvImportFlowNotifier, CsvImportFlowState>(
      CsvImportFlowNotifier.new,
    );
