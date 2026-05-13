import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart';
import 'package:veraprob/domain/shared/brazil_time.dart';

void main() {
  group('BrazilTime', () {
    test('ensureInitialized is idempotent', () {
      BrazilTime.ensureInitialized();
      BrazilTime.ensureInitialized(); // no throw
    });

    test('nowBrazil returns TZDateTime in America/Sao_Paulo', () {
      final result = BrazilTime.nowBrazil();
      expect(result, isA<TZDateTime>());
      expect(result.location.name, 'America/Sao_Paulo');
    });

    test('toOperationalDateUtc strips time and returns UTC', () {
      BrazilTime.ensureInitialized();
      final sp = getLocation('America/Sao_Paulo');
      final brt = TZDateTime(sp, 2026, 3, 1, 23, 30);

      final result = BrazilTime.toOperationalDateUtc(brt);

      expect(result.isUtc, isTrue);
      expect(result, DateTime.utc(2026, 3, 1));
    });

    test('isSameOperationalDay handles BRTâ†’UTC boundary', () {
      BrazilTime.ensureInitialized();
      // 2026-03-02 01:30 UTC = 2026-03-01 22:30 BRT (same op day as March 1)
      final utcTimestamp = DateTime.utc(2026, 3, 2, 1, 30);
      final opDate = DateTime.utc(2026, 3, 1);

      expect(BrazilTime.isSameOperationalDay(utcTimestamp, opDate), isTrue);
    });

    test('isSameOperationalDay returns false for different day', () {
      BrazilTime.ensureInitialized();
      // 2026-03-02 06:00 UTC = 2026-03-02 03:00 BRT (op day March 2)
      final utcTimestamp = DateTime.utc(2026, 3, 2, 6, 0);
      final opDate = DateTime.utc(2026, 3, 1);

      expect(BrazilTime.isSameOperationalDay(utcTimestamp, opDate), isFalse);
    });
  });
}
