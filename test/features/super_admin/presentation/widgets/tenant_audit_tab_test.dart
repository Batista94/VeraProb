import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/audit_category_badge.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_audit_tab.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ─── Test Data ──────────────────────────────────────────────────────────────

const _testOrgId = 'test-org-id';
const _validUuid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

SystemAuditLogView _makeLog({
  String eventType = 'GENERIC_EVENT',
  String severity = 'info',
  String? actorType,
  String? source,
  String? reason,
  Map<String, Object?>? payload,
}) {
  return SystemAuditLogView(
    severity: severity,
    eventType: eventType,
    occurredAt: '2024-06-15T10:30:00Z',
    organizationId: _testOrgId,
    actorType: actorType,
    source: source,
    reason: reason,
    payload: payload,
  );
}

/// Wraps [TenantAuditTab] in a [MaterialApp] + [ProviderScope] with
/// the systemAuditLogProvider overridden to return [logs].
Widget _buildTestWidget({required List<SystemAuditLogView> logs}) {
  return ProviderScope(
    overrides: [
      systemAuditLogProvider.overrideWith((ref, params) async => logs),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 1200,
          child: TenantAuditTab(organizationId: _testOrgId),
        ),
      ),
    ),
  );
}

/// Pumps the widget tree enough frames for the FutureProvider to resolve.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // AuditCategoryBadge rendering with different categories
  // **Validates: Requirements 7.1**
  // ═══════════════════════════════════════════════════════════════════════════

  group('AuditCategoryBadge rendering with different categories', () {
    testWidgets('infrastructure event renders Infraestrutura badge', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(logs: [_makeLog(eventType: 'POOL_LIMIT_EXCEEDED')]),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      expect(find.byType(AuditCategoryBadge), findsOneWidget);
      expect(find.text('Infraestrutura'), findsOneWidget);
    });

    testWidgets('security event renders Segurança badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(logs: [_makeLog(eventType: 'SECRET_ROTATED')]),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      expect(find.byType(AuditCategoryBadge), findsOneWidget);
      expect(find.text('Segurança'), findsOneWidget);
    });

    testWidgets('governance event renders Governança badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(logs: [_makeLog(eventType: 'PLAN_CHANGED')]),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      expect(find.byType(AuditCategoryBadge), findsOneWidget);
      expect(find.text('Governança'), findsOneWidget);
    });

    testWidgets('unknown event renders Operacional badge (fallback)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(logs: [_makeLog(eventType: 'SOME_RANDOM_EVENT')]),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      expect(find.byType(AuditCategoryBadge), findsOneWidget);
      expect(find.text('Operacional'), findsOneWidget);
    });

    testWidgets('multiple logs render one badge per item', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(
          logs: [
            _makeLog(eventType: 'POOL_LIMIT_EXCEEDED'),
            _makeLog(eventType: 'SECRET_ROTATED'),
            _makeLog(eventType: 'PLAN_CHANGED'),
          ],
        ),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      expect(find.byType(AuditCategoryBadge), findsNWidgets(3));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Linkable actor field — UUID vs. static text
  // **Validates: Requirements 8.1**
  // ═══════════════════════════════════════════════════════════════════════════

  group('Linkable actor field', () {
    testWidgets(
      'valid UUID actorType renders GestureDetector with underline styling',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestWidget(logs: [_makeLog(actorType: _validUuid)]),
        );
        await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

        // Expand the ExpansionTile to reveal actor row
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();

        // The UUID actor should be rendered as a tappable link
        expect(find.text(_validUuid), findsOneWidget);
        expect(find.byType(GestureDetector), findsWidgets);

        // Verify the UUID text has underline decoration
        final uuidText = tester.widget<Text>(find.text(_validUuid));
        expect(
          uuidText.style?.decoration,
          TextDecoration.underline,
          reason: 'UUID actor should have underline decoration',
        );
      },
    );

    testWidgets(
      'SYSTEM actorType renders plain text without GestureDetector link',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestWidget(logs: [_makeLog(actorType: 'SYSTEM')]),
        );
        await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

        // Expand the ExpansionTile to reveal actor row
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();

        // SYSTEM should be rendered as plain text
        expect(find.text('SYSTEM'), findsOneWidget);

        // The SYSTEM text should NOT have underline decoration
        final systemText = tester.widget<Text>(find.text('SYSTEM'));
        expect(
          systemText.style?.decoration,
          isNot(TextDecoration.underline),
          reason: 'SYSTEM actor should not have underline decoration',
        );
      },
    );

    testWidgets('null actorType defaults to SYSTEM as plain text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(logs: [_makeLog(actorType: null)]),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      // Expand the ExpansionTile
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Should default to SYSTEM text
      expect(find.text('SYSTEM'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Copy-to-clipboard for Snapshot_ID / Request_ID
  // **Validates: Requirements 8.5**
  // ═══════════════════════════════════════════════════════════════════════════

  group('Copy-to-clipboard for Snapshot_ID / Request_ID', () {
    testWidgets('tapping Snapshot ID copies to clipboard and shows SnackBar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Track clipboard writes via the platform channel
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardContent = (methodCall.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      const snapshotId = 'snap-abc-123-def-456';

      await tester.pumpWidget(
        _buildTestWidget(
          logs: [
            _makeLog(payload: {'snapshot_id': snapshotId}),
          ],
        ),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      // Expand the ExpansionTile to reveal the copyable ID row
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Verify the snapshot ID is displayed
      expect(find.text(snapshotId), findsOneWidget);

      // Tap on the snapshot ID row (the GestureDetector wrapping the row)
      await tester.tap(find.text(snapshotId));
      await tester.pumpAndSettle();

      // Verify clipboard was written
      expect(clipboardContent, snapshotId);

      // Verify SnackBar feedback
      expect(
        find.text('ID copiado para a área de transferência'),
        findsOneWidget,
      );
    });

    testWidgets('tapping Request ID copies to clipboard and shows SnackBar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardContent = (methodCall.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      const requestId = 'req-xyz-789-uvw-012';

      await tester.pumpWidget(
        _buildTestWidget(
          logs: [
            _makeLog(payload: {'request_id': requestId}),
          ],
        ),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      // Expand the ExpansionTile
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Verify the request ID is displayed
      expect(find.text(requestId), findsOneWidget);

      // Tap on the request ID row
      await tester.tap(find.text(requestId));
      await tester.pumpAndSettle();

      // Verify clipboard was written
      expect(clipboardContent, requestId);

      // Verify SnackBar feedback
      expect(
        find.text('ID copiado para a área de transferência'),
        findsOneWidget,
      );
    });

    testWidgets('Snapshot ID is rendered in monospace font', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const snapshotId = 'snap-mono-test-123';

      await tester.pumpWidget(
        _buildTestWidget(
          logs: [
            _makeLog(payload: {'snapshot_id': snapshotId}),
          ],
        ),
      );
      await _pumpUntilFound(tester, find.byType(AuditCategoryBadge));

      // Expand the ExpansionTile
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Verify the snapshot ID text uses monospace font
      final idText = tester.widget<Text>(find.text(snapshotId));
      expect(
        idText.style?.fontFamily,
        'monospace',
        reason: 'Snapshot ID should use monospace font',
      );
    });
  });
}
