
import 'package:glados/glados.dart';
import 'package:intl/intl.dart';

/// **Validates: Requirements 6.4**
///
/// Property 3: Formatação de data no padrão brasileiro
///
/// For any valid [DateTime], formatting with `DateFormat('dd/MM/yyyy HH:mm')`
/// SHALL produce a string that:
///
/// 1. Matches the regex `^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$`
/// 2. Has each extracted component matching the original DateTime:
///    - day   == dt.day
///    - month == dt.month
///    - year  == dt.year
///    - hour  == dt.hour
///    - minute == dt.minute
///
/// Uses the same safe-range generator as Task 2.4:
/// year 2000–2030, month 1–12, day 1–28, hour 0–23, minute 0–59.
void main() {
  /// Custom DateTime generator using safe component ranges:
  /// year 2000–2030, month 1–12, day 1–28, hour 0–23, minute 0–59.
  final safeDateTime = any.combine5(
    any.intInRange(2000, 2031), // year
    any.intInRange(1, 13), // month
    any.intInRange(1, 29), // day (safe for all months)
    any.intInRange(0, 24), // hour
    any.intInRange(0, 60), // minute
    (int year, int month, int day, int hour, int minute) =>
        DateTime(year, month, day, hour, minute),
  );

  final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final brazilianDateRegex = RegExp(r'^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$');

  group('Feature: tenant-config-immutable-fields, '
      'Property 3: Formatação de data no padrão brasileiro', () {
    // Pre-generate 100+ DateTimes for testWidgets-compatible iteration.
    // Glados.test uses package:test's `test`, so we pre-generate values
    // to ensure minimum 100 iterations.
    final random = Random(42);
    final dateTimes = <DateTime>[
      for (var i = 0; i < 100; i++) safeDateTime(random, i + 5).value,
    ];

    for (var i = 0; i < dateTimes.length; i++) {
      final dt = dateTimes[i];

      test('iter $i: DateFormat("dd/MM/yyyy HH:mm") formats '
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')} correctly', () {
        final formatted = dateFormat.format(dt);

        // ── Property 3a: Regex format validation ──
        expect(
          brazilianDateRegex.hasMatch(formatted),
          isTrue,
          reason:
              'Formatted date "$formatted" must match '
              r'^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$',
        );

        // ── Property 3b: Component-level temporal validity ──
        // Extract components from the formatted string and verify
        // each matches the original DateTime — prevents 99/99/9999
        // from passing.
        final parsedDay = int.parse(formatted.substring(0, 2));
        final parsedMonth = int.parse(formatted.substring(3, 5));
        final parsedYear = int.parse(formatted.substring(6, 10));
        final parsedHour = int.parse(formatted.substring(11, 13));
        final parsedMinute = int.parse(formatted.substring(14, 16));

        expect(
          parsedDay,
          equals(dt.day),
          reason: 'Day component ($parsedDay) must match dt.day (${dt.day})',
        );
        expect(
          parsedMonth,
          equals(dt.month),
          reason:
              'Month component ($parsedMonth) must match '
              'dt.month (${dt.month})',
        );
        expect(
          parsedYear,
          equals(dt.year),
          reason:
              'Year component ($parsedYear) must match '
              'dt.year (${dt.year})',
        );
        expect(
          parsedHour,
          equals(dt.hour),
          reason:
              'Hour component ($parsedHour) must match '
              'dt.hour (${dt.hour})',
        );
        expect(
          parsedMinute,
          equals(dt.minute),
          reason:
              'Minute component ($parsedMinute) must match '
              'dt.minute (${dt.minute})',
        );
      });
    }
  });
}
