import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/features/admin/presentation/utils/csv_error_exporter.dart';

void main() {
  group('CsvErrorExporter.buildCsv', () {
    // E1 — 3 errors → CSV with header + 3 data rows
    test('E1: produces header + 3 data rows for 3 errors', () {
      final errors = [
        const CsvRowError(
          rowIndex: 1,
          csvHeader: 'PLACA',
          targetField: 'identifier',
          errorCode: 'required',
          message: 'Valor obrigatório não preenchido.',
        ),
        const CsvRowError(
          rowIndex: 2,
          csvHeader: 'CNPJ',
          targetField: 'operator_document',
          errorCode: 'invalid_cnpj',
          message: 'CNPJ inválido.',
        ),
        const CsvRowError(
          rowIndex: 5,
          csvHeader: 'DATA',
          targetField: 'start_date',
          errorCode: 'invalid_date',
          message: 'Data inválida.',
        ),
      ];

      final csv = CsvErrorExporter.buildCsv(errors);
      final lines = csv.trim().split('\n');

      // Header + 3 data lines
      expect(lines.length, equals(4));
      expect(
        lines.first,
        equals('linha,coluna_csv,campo_alvo,codigo_erro,mensagem'),
      );
      expect(lines[1], contains('1'));
      expect(lines[1], contains('PLACA'));
      expect(lines[2], contains('2'));
      expect(lines[2], contains('CNPJ'));
      expect(lines[3], contains('5'));
      expect(lines[3], contains('DATA'));
    });

    // E2 — message with comma → quoted with double-quote escaping
    test('E2: message containing comma is quoted', () {
      final errors = [
        const CsvRowError(
          rowIndex: 3,
          csvHeader: 'OBS',
          targetField: 'notes',
          errorCode: 'injection_detected',
          message: 'Valor bloqueado, fórmula suspeita',
        ),
      ];

      final csv = CsvErrorExporter.buildCsv(errors);
      // The message field must be wrapped in double quotes.
      expect(csv, contains('"Valor bloqueado, fórmula suspeita"'));
    });

    // E3 — message with double-quote → escaped as double-double-quote
    test('E3: message containing double-quote is escaped', () {
      final errors = [
        const CsvRowError(
          rowIndex: 7,
          csvHeader: 'NOME',
          targetField: 'name',
          errorCode: 'xss_detected',
          message: 'Valor com "aspas" detectado',
        ),
      ];

      final csv = CsvErrorExporter.buildCsv(errors);
      // Double-quote inside quoted field must be escaped as "".
      expect(csv, contains('"Valor com ""aspas"" detectado"'));
    });

    // E4 — empty error list → only header row
    test('E4: empty errors list produces only the header row', () {
      final csv = CsvErrorExporter.buildCsv([]);
      final lines = csv.trim().split('\n');
      expect(lines.length, equals(1));
      expect(lines.first, startsWith('linha,coluna_csv'));
    });
  });
}
