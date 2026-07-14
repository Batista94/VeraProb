// Goldens for SuperAdminAuditLogScreen — generate EXCLUSIVAMENTE via `make goldens`.

import 'dart:async';
import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/features/super_admin/presentation/screens/super_admin_audit_log_screen.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

SystemAuditLogView _view({
  required String eventType,
  String severity = 'info',
  String? actorType,
  Map<String, Object?>? payload,
}) {
  return SystemAuditLogView(
    severity: severity,
    eventType: eventType,
    occurredAt: DateTime.utc(2026, 5, 1, 12).toIso8601String(),
    actorType: actorType,
    payload: payload,
  );
}

Widget _buildScreen({
  required FutureOr<List<SystemAuditLogView>> Function(
    Ref ref,
    AuditLogParams params,
  )
  providerOverride,
}) {
  return ProviderScope(
    overrides: [systemAuditLogProvider.overrideWith(providerOverride)],
    child: const MaterialApp(home: Scaffold(body: SuperAdminAuditLogScreen())),
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('Golden Tests — Visual Regression', () {
    goldenTest(
      'Golden: severity highlighting with all severities present',
      fileName: 'audit_log_all_severities',
      builder: () {
        final entries = [
          _view(eventType: 'DEBUG_TRACE', severity: 'debug'),
          _view(eventType: 'EVALUATION_RUN', severity: 'info'),
          _view(eventType: 'STORAGE_QUOTA_EXCEEDED', severity: 'warning'),
          _view(eventType: 'PROXY_ERROR', severity: 'error'),
          _view(
            eventType: 'MFA_LOCKED',
            severity: 'critical',
            actorType: 'SYSTEM',
          ),
        ];
        return SizedBox(
          width: 1400,
          height: 1200,
          child: _buildScreen(providerOverride: (ref, _) async => entries),
        );
      },
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden: empty state centered with correct typography',
      fileName: 'audit_log_empty_state',
      builder: () => SizedBox(
        width: 1400,
        height: 900,
        child: _buildScreen(providerOverride: (ref, _) async => const []),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden: error state visual',
      fileName: 'audit_log_error_state',
      builder: () => SizedBox(
        width: 1400,
        height: 900,
        child: _buildScreen(
          providerOverride: (ref, _) async => throw StateError('network'),
        ),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden: payload diff dialog uses monospace font',
      fileName: 'audit_log_payload_diff',
      builder: () {
        final payload = <String, Object?>{
          'before': {'status': 'active', 'quota_gb': 10},
          'after': {'status': 'suspended', 'quota_gb': 5},
        };
        return SizedBox(
          width: 1400,
          height: 900,
          child: _buildScreen(
            providerOverride: (ref, _) async => [
              _view(
                eventType: 'STATUS_CHANGE',
                payload: payload,
                actorType: 'HUMAN',
              ),
            ],
          ),
        );
      },
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.data_object));
        await tester.pumpAndSettle();
      },
    );
  });
}
