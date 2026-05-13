import 'package:timezone/timezone.dart';
import 'package:timezone/data/latest.dart' as tz;

/// Temporal infrastructure for Brazilian operational timezone.
///
/// All financial snapshots use America/Sao_Paulo as the operational
/// timezone. This utility ensures deterministic date boundaries
/// for daily financial closing.
class BrazilTime {
  static bool _initialized = false;
  static late Location _saoPaulo;

  /// Initializes timezone data. Safe to call multiple times.
  static void ensureInitialized() {
    if (_initialized) return;
    tz.initializeTimeZones();
    _saoPaulo = getLocation('America/Sao_Paulo');
    _initialized = true;
  }

  /// Returns the current time in America/Sao_Paulo.
  static TZDateTime nowBrazil() {
    ensureInitialized();
    return TZDateTime.now(_saoPaulo);
  }

  /// Converts a BRT datetime to a normalized UTC operational date (00:00Z).
  ///
  /// Example: 2026-03-01 23:30 BRT → DateTime.utc(2026, 3, 1)
  static DateTime toOperationalDateUtc(TZDateTime brtDate) {
    return DateTime.utc(brtDate.year, brtDate.month, brtDate.day);
  }

  /// Checks whether a UTC timestamp falls on the same operational day
  /// when converted to America/Sao_Paulo timezone.
  static bool isSameOperationalDay(
    DateTime utcTimestamp,
    DateTime operationalDateUtc,
  ) {
    ensureInitialized();
    final brt = TZDateTime.from(utcTimestamp, _saoPaulo);
    final brtDate = DateTime.utc(brt.year, brt.month, brt.day);
    return brtDate == operationalDateUtc;
  }

  /// The canonical operational timezone identifier.
  static const String operationalTimezone = 'America/Sao_Paulo';
}
