import 'package:veraprob/core/time/brazil_time.dart';

/// Abstract interface for deterministic time injection.
///
/// Enables testing with fake clocks and ensures all timestamps use UTC
/// for forensic integrity (INV-3).
///
/// Contract:
/// - [now()] returns a UTC [DateTime] with `isUtc: true` — the default for
///   database writes, ledger entries, and audit trails.
/// - [nowBrazil()] returns a non-UTC [DateTime] with `isUtc: false`,
///   containing wall-clock values adjusted to America/Sao_Paulo (UTC-3).
///   Use strictly for display logic or business rules that depend on
///   Brazilian local time (e.g., "no trips after 22h BRT").
abstract class IDateTimeProvider {
  /// Returns current UTC time.
  DateTime nowUtc();

  /// Returns current time in America/Sao_Paulo as a plain DateTime
  /// with `isUtc: false` and wall-clock values already adjusted.
  DateTime nowBrazil();
}

/// Static accessor for use in domain entities that cannot accept DI via
/// constructor. This is a pragmatic escape hatch until full DI is available.
///
/// Set this in tests with a [FakeDateTimeProvider] and reset to null after.
/// In production, falls back to [BrazilDateTimeProvider].
class StaticDateTimeProvider {
  static IDateTimeProvider? instance;

  static void override(IDateTimeProvider provider) {
    instance = provider;
  }

  static void reset() {
    instance = null;
  }
}

/// Production implementation using system clock.
class BrazilDateTimeProvider implements IDateTimeProvider {
  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  DateTime nowBrazil() {
    BrazilTime.ensureInitialized();
    final tzNow = BrazilTime.nowBrazil();
    // Convert TZDateTime to a plain DateTime with isUtc: false,
    // preserving wall-clock values (year, month, day, hour, minute, etc.)
    return DateTime(
      tzNow.year,
      tzNow.month,
      tzNow.day,
      tzNow.hour,
      tzNow.minute,
      tzNow.second,
      tzNow.millisecond,
      tzNow.microsecond,
    );
  }
}

/// Strict UTC implementation — Zero Time Leaks.
/// Returns system clock in UTC, without any local time helpers.
class UtcDateTimeProvider implements IDateTimeProvider {
  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  DateTime nowBrazil() {
    throw UnsupportedError(
      'UtcDateTimeProvider does not support Brazil local time. USE BrazilDateTimeProvider for UI/display only.',
    );
  }
}
