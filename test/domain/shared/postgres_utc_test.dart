import 'package:test/test.dart';
import 'package:veraprob/domain/shared/postgres_utc.dart';

void main() {
  group('postgres_utc', () {
    test('parsePostgresUtc appends Z to naive timestamps (INV-6)', () {
      final result = parsePostgresUtc('2026-07-14T10:00:00');
      expect(result.isUtc, isTrue);
      expect(result, DateTime.utc(2026, 7, 14, 10, 0, 0));
    });

    test('parsePostgresUtc respects existing Z suffix', () {
      final result = parsePostgresUtc('2026-07-14T10:00:00Z');
      expect(result.isUtc, isTrue);
      expect(result, DateTime.utc(2026, 7, 14, 10, 0, 0));
    });

    test('parsePostgresUtc respects explicit positive timezone offsets', () {
      final result = parsePostgresUtc('2026-07-14T10:00:00+03:00');
      expect(result.isUtc, isTrue);
      expect(
        result,
        DateTime.utc(2026, 7, 14, 7, 0, 0),
      ); // 10:00+03:00 is 07:00 UTC
    });

    test('parsePostgresUtc fails when input is not a String', () {
      expect(() => parsePostgresUtc(null), throwsA(isA<TypeError>()));

      expect(() => parsePostgresUtc(123456789), throwsA(isA<TypeError>()));
    });
  });
}
