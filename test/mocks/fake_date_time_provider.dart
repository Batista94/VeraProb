import 'package:veraprob/core/utils/date_time_provider.dart';

/// Fake [IDateTimeProvider] for deterministic testing.
///
/// Holds a fixed time that only changes when explicitly advanced via [advance()]
/// or set via [set()]. This removes system-time dependency from tests.
class FakeDateTimeProvider implements IDateTimeProvider {
  DateTime _fixedTime;

  /// Creates a fake provider fixed at [fixedTime].
  /// If [isUtc] is true (default), [fixedTime] is treated as UTC.
  FakeDateTimeProvider(DateTime fixedTime, {bool isUtc = true})
    : _fixedTime = isUtc ? fixedTime.toUtc() : fixedTime;

  @override
  DateTime nowUtc() => _fixedTime.toUtc();

  @override
  DateTime nowBrazil() => DateTime(
    _fixedTime.year,
    _fixedTime.month,
    _fixedTime.day,
    _fixedTime.hour,
    _fixedTime.minute,
    _fixedTime.second,
    _fixedTime.millisecond,
    _fixedTime.microsecond,
  );

  /// Advances the fixed time by [duration].
  void advance(Duration duration) {
    _fixedTime = _fixedTime.add(duration);
  }

  /// Sets the fixed time to [time].
  void set(DateTime time) {
    _fixedTime = time;
  }

  /// Returns the current fixed time.
  DateTime get fixedTime => _fixedTime;
}
