import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  group('ColumnMapping', () {
    test('fromJson - Happy path', () {
      final json = {
        'csv_header': 'PLACA',
        'target_field': 'identifier',
        'transform': 'uppercase',
        'required': true,
      };

      final mapping = ColumnMapping.fromJson(json);

      expect(mapping.csvHeader, 'PLACA');
      expect(mapping.targetField, CsvTargetField.identifier);
      expect(mapping.transform, 'uppercase');
      expect(mapping.required, true);
    });

    test('fromJson - Rejects empty csv_header', () {
      final json = {'csv_header': '', 'target_field': 'identifier'};

      expect(
        () => ColumnMapping.fromJson(json),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'message',
            contains('csv_header is required'),
          ),
        ),
      );
    });

    test('fromJson - Rejects invalid target_field', () {
      final json = {'csv_header': 'PLACA', 'target_field': 'invalid_field'};

      expect(
        () => ColumnMapping.fromJson(json),
        throwsA(isA<IntegrityException>()),
      );
    });

    test(
      'fromJson - Hacking/Adverse: Strips HTML from csv_header (Stored XSS)',
      () {
        final json = {
          'csv_header': '<script>alert(1)</script>PLACA',
          'target_field': 'identifier',
        };

        final mapping = ColumnMapping.fromJson(json);

        // It should strip out the HTML tags
        expect(mapping.csvHeader, 'alert(1)PLACA');
      },
    );

    test(
      'fromJson - Hacking/Adverse: Handles only HTML tags in header by rejecting empty result',
      () {
        final json = {
          'csv_header': '<script></script>',
          'target_field': 'identifier',
        };

        // After stripping HTML, it becomes empty, which is rejected
        expect(
          () => ColumnMapping.fromJson(json),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('csv_header is required'),
            ),
          ),
        );
      },
    );
  });
}
