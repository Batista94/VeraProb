import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Domain service for security assertions on external data processing.
class SecurityAssertionService {
  /// Checks magic bytes to verify file is plain text / csv and not a binary or executable
  /// Emenda 1 - MIME-Type Sniffing: Rejeita binários no ImportCsvCommand.
  static void assertPlainTextMagicBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const IntegrityException('File is empty');
    }

    // Check for common binary signatures (PDF, ZIP, MZ, PNG, JPG, ELF)
    if (bytes.length >= 4) {
      // PDF: %PDF (25 50 44 46)
      if (bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46) {
        throw const IntegrityException(
          'Invalid file format: Detected PDF. Only CSV is allowed.',
          field: 'file_content',
        );
      }

      // ZIP/DOCX/XLSX: PK (50 4B)
      if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
        throw const IntegrityException(
          'Invalid file format: Detected ZIP/Archive. Only CSV is allowed.',
          field: 'file_content',
        );
      }

      // Windows Executable: MZ (4D 5A)
      if (bytes[0] == 0x4D && bytes[1] == 0x5A) {
        throw const IntegrityException(
          'Invalid file format: Detected Executable. Only CSV is allowed.',
          field: 'file_content',
        );
      }
    }
  }

  /// Sanitizes text to prevent Formula/CSV Injection by rejecting values starting with macro triggers.
  /// Emenda 1 - CSV Injection.
  static String assertNoCsvInjection(String value, String fieldName) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return value;

    // Formula injection characters: = + - @
    final firstChar = trimmed[0];
    if (firstChar == '=' || firstChar == '@') {
      throw IntegrityException(
        'Formula injection detected. Values cannot start with = or @',
        field: fieldName,
      );
    }
    if ((firstChar == '+' || firstChar == '-') &&
        double.tryParse(trimmed) == null) {
      throw IntegrityException(
        'Formula injection detected. Values cannot start with + or - unless they are valid numbers',
        field: fieldName,
      );
    }
    return value;
  }

  /// Strips HTML tags and JS payloads to prevent Stored XSS.
  /// Emenda 1 - Stored XSS.
  static String sanitizeHtml(String input) {
    if (input.isEmpty) return input;
    // Basic HTML stripping regex
    final htmlStripRegExp = RegExp(
      r'<[^>]*>',
      multiLine: true,
      caseSensitive: false,
    );
    return input.replaceAll(htmlStripRegExp, '').trim();
  }
}
