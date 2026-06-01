import 'package:flutter/foundation.dart';

class LoggerService {
  // Singleton pattern
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  void log(String message, {String? component}) {
    if (kReleaseMode) {
      // In production, send to Crashlytics or Supabase Logs
      // Future: integrate production log draining service
      return;
    }
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final prefix = component != null ? '[$component]' : '[App]';
    debugPrint('$timestamp $prefix $message');
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    // Critical errors should always be logged or reported
    final timestamp = DateTime.now().toUtc().toIso8601String();
    debugPrint('🔴 $timestamp [ERROR] $message');
    if (error != null) debugPrint('Error: $error');
    if (stackTrace != null) debugPrint('StackTrace: $stackTrace');

    // Pending: Send to external monitoring service (Sentry/NewRelic)
    _reportToExternalService(message, error, stackTrace);
  }

  void _reportToExternalService(
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    // structured hook for future Sentry.captureException or FirebaseCrashlytics
    if (kReleaseMode) {
      // Sentry.captureException(error, stackTrace: stackTrace);
    }
  }

  void security(String event) {
    // Specific stream for security events (A09: Security Logging)
    final timestamp = DateTime.now().toUtc().toIso8601String();
    debugPrint('🔒 $timestamp [SECURITY] $event');
    // Ideally persist this to specific audit table in Supabase
  }
}
