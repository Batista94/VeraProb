import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

void main() {
  group('BrazilDateTimeProvider', () {
    late BrazilDateTimeProvider provider;

    setUp(() => provider = BrazilDateTimeProvider());

    test('nowUtc returns UTC DateTime', () {
      final result = provider.nowUtc();
      expect(result.isUtc, isTrue);
    });

    test('nowBrazil returns non-UTC DateTime', () {
      final result = provider.nowBrazil();
      expect(result.isUtc, isFalse);
    });
  });

  group('UtcDateTimeProvider', () {
    late UtcDateTimeProvider provider;

    setUp(() => provider = UtcDateTimeProvider());

    test('nowUtc returns UTC DateTime', () {
      final result = provider.nowUtc();
      expect(result.isUtc, isTrue);
    });

    test('nowBrazil throws UnsupportedError', () {
      expect(() => provider.nowBrazil(), throwsUnsupportedError);
    });
  });

  group('StaticDateTimeProvider', () {
    tearDown(() => StaticDateTimeProvider.reset());

    test('override sets instance', () {
      final fake = _FakeProvider(DateTime.utc(2026, 1, 1));
      StaticDateTimeProvider.override(fake);
      expect(StaticDateTimeProvider.instance, same(fake));
    });

    test('reset clears instance', () {
      StaticDateTimeProvider.override(_FakeProvider(DateTime.utc(2026, 1, 1)));
      StaticDateTimeProvider.reset();
      expect(StaticDateTimeProvider.instance, isNull);
    });
  });
}

class _FakeProvider implements IDateTimeProvider {
  final DateTime _fixed;
  _FakeProvider(this._fixed);

  @override
  DateTime nowUtc() => _fixed;

  @override
  DateTime nowBrazil() => _fixed;
}
