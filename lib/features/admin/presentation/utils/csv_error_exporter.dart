import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';

/// Generates and downloads a CSV file containing import errors (Emenda 2).
/// Pure Dart CSV generation + file_saver for cross-platform download (INV-17).
class CsvErrorExporter {
  static String buildCsv(List<CsvRowError> errors) {
    final buffer = StringBuffer();
    buffer.writeln('linha,coluna_csv,campo_alvo,codigo_erro,mensagem');
    for (final e in errors) {
      buffer.writeln(
        '${e.rowIndex},'
        '${_escape(e.csvHeader)},'
        '${_escape(e.targetField)},'
        '${_escape(e.errorCode)},'
        '${_escape(e.message)}',
      );
    }
    return buffer.toString();
  }

  static Future<void> download(
    List<CsvRowError> errors,
    String fileName,
  ) async {
    final csv = buildCsv(errors);
    final bytes = utf8.encode(csv);
    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
