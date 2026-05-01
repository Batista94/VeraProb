import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/tenant_technical_health_view.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/pulse_indicator.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_health_tab.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

// ─── Test Helpers ───────────────────────────────────────────────────────────

const _testOrgId = 'test-org-id';

/// Creates a [TenantTechnicalHealthView] with configurable health states.
TenantTechnicalHealthView _makeHealth({
  ReplicationStatus replication = ReplicationStatus.healthy,
  SchemaIntegrityStatus schema = SchemaIntegrityStatus.compliant,
  String version = 'v2024.06.15-r3',
  DateTime? lastCheckAt,
}) {
  return TenantTechnicalHealthView(
    replicationStatus: replication,
    schemaIntegrityStatus: schema,
    schemaVersion: version,
    lastCheckAt: lastCheckAt,
  );
}

/// Wraps [TenantHealthTab] in a [MaterialApp] + [ProviderScope] with
/// all required provider overrides so the widget can render in isolation.
Widget _buildTestWidget({
  bool isSuperAdmin = true,
  TenantTechnicalHealthView? health,
  MockSuperAdminRepository? repo,
}) {
  final mockRepo = repo ?? MockSuperAdminRepository();
  final healthView = health ?? _makeHealth();

  return ProviderScope(
    overrides: [
      isSuperAdminProvider.overrideWithValue(isSuperAdmin),
      tenantTechnicalHealthProvider.overrideWith(
        (ref, orgId) async => healthView,
      ),
      superAdminRepositoryProvider.overrideWithValue(mockRepo),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 1200,
          child: TenantHealthTab(organizationId: _testOrgId),
        ),
      ),
    ),
  );
}

/// Pumps the widget tree enough frames for the FutureProvider to resolve
/// and the widget to build, without waiting for animations to settle
/// (PulseIndicator has a repeating animation that never settles).
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
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
  // PulseIndicator rendering with different health states
  // **Validates: Requirements 2.1, 2.2**
  // ═══════════════════════════════════════════════════════════════════════════

  group('PulseIndicator rendering with different health states', () {
    testWidgets('healthy replication + compliant schema renders green labels', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(
          health: _makeHealth(
            replication: ReplicationStatus.healthy,
            schema: SchemaIntegrityStatus.compliant,
          ),
        ),
      );
      // Use pump() instead of pumpAndSettle() — PulseIndicator has a
      // repeating animation that never settles.
      await _pumpUntilFound(tester, find.byType(PulseIndicator));

      // Verify both PulseIndicators are rendered
      expect(find.byType(PulseIndicator), findsNWidgets(2));

      // Verify labels — "Integridade de Schema" appears twice: once as
      // section title and once as PulseIndicator label.
      expect(find.text('Status de Replicação'), findsOneWidget);
      expect(find.text('Integridade de Schema'), findsNWidgets(2));

      // Verify subtitles for healthy states
      expect(find.text('Replicação saudável'), findsOneWidget);
      expect(find.text('Schema conforme'), findsOneWidget);
    });

    testWidgets(
      'delayed replication + minor drift schema renders warning labels',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestWidget(
            health: _makeHealth(
              replication: ReplicationStatus.delayed,
              schema: SchemaIntegrityStatus.minorDrift,
            ),
          ),
        );
        await _pumpUntilFound(tester, find.byType(PulseIndicator));

        expect(find.byType(PulseIndicator), findsNWidgets(2));
        expect(find.text('Replicação com atraso'), findsOneWidget);
        expect(find.text('Divergência menor detectada'), findsOneWidget);
      },
    );

    testWidgets(
      'failed replication + critical drift schema renders critical labels',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestWidget(
            health: _makeHealth(
              replication: ReplicationStatus.failed,
              schema: SchemaIntegrityStatus.criticalDrift,
            ),
          ),
        );
        await _pumpUntilFound(tester, find.byType(PulseIndicator));

        expect(find.byType(PulseIndicator), findsNWidgets(2));
        expect(find.text('Falha na replicação'), findsOneWidget);
        expect(find.text('Divergência crítica detectada'), findsOneWidget);
      },
    );

    testWidgets('displays schema version text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(health: _makeHealth(version: 'v2024.06.15-r3')),
      );
      await _pumpUntilFound(tester, find.text('v2024.06.15-r3'));

      expect(find.text('v2024.06.15-r3'), findsOneWidget);
      expect(find.text('Versão: '), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Debounce behavior of "Verificar Integridade" button
  // **Validates: Requirements 3.1**
  // ═══════════════════════════════════════════════════════════════════════════

  group('Debounce behavior of "Verificar Integridade" button', () {
    testWidgets('button disables during cooldown and re-enables after 3s', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockRepo = MockSuperAdminRepository();
      when(
        () => mockRepo.checkSchemaIntegrity(_testOrgId),
      ).thenAnswer((_) async => <String, dynamic>{});

      await tester.pumpWidget(_buildTestWidget(repo: mockRepo));
      // Wait for the FutureProvider to resolve and data to render
      await _pumpUntilFound(tester, find.text('Verificar Integridade'));

      // Button should be enabled initially
      expect(find.text('Verificar Integridade'), findsOneWidget);

      // Tap the button text directly
      await tester.tap(find.text('Verificar Integridade'));
      await tester.pump(); // Process the tap

      // The mock resolves immediately, so _isChecking flips to false and
      // _cooldownActive flips to true in the same microtask. However,
      // ref.invalidate causes the provider to re-fetch (loading state).
      // Pump enough frames for the FutureProvider to resolve again.
      await _pumpUntilFound(tester, find.text('Aguarde...'));

      // After check completes, cooldown should be active — button shows "Aguarde..."
      expect(find.text('Aguarde...'), findsOneWidget);

      // ElevatedButton.icon creates an ElevatedButton in the widget tree.
      // Use ButtonStyleButton as a broader matcher.
      final disabledButton = find.bySubtype<ButtonStyleButton>();
      expect(disabledButton, findsOneWidget);
      var button = tester.widget<ButtonStyleButton>(disabledButton);
      expect(
        button.onPressed,
        isNull,
        reason: 'Button should be disabled during cooldown',
      );

      // Advance timer past the 3-second cooldown
      await tester.pump(const Duration(seconds: 3));

      // Button should be re-enabled with original text
      expect(find.text('Verificar Integridade'), findsOneWidget);

      button = tester.widget<ButtonStyleButton>(
        find.bySubtype<ButtonStyleButton>(),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: 'Button should be re-enabled after 3s cooldown',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Blur state when JWT does not contain SuperAdmin claim
  // **Validates: Requirements 4.2**
  // ═══════════════════════════════════════════════════════════════════════════

  group('Blur state when JWT does not contain SuperAdmin claim', () {
    testWidgets('renders BackdropFilter blur overlay when not SuperAdmin', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWidget(isSuperAdmin: false));
      // No PulseIndicator animation here — blur overlay is static, so
      // pumpAndSettle is safe.
      await tester.pumpAndSettle();

      // BackdropFilter should be present for blur effect
      expect(find.byType(BackdropFilter), findsOneWidget);

      // Lock icon should be visible
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // Unauthorized message should be displayed
      expect(find.text('Acesso não autorizado'), findsOneWidget);
      expect(
        find.text(
          'Você não possui permissão para visualizar\n'
          'dados de saúde técnica.',
        ),
        findsOneWidget,
      );

      // PulseIndicators should NOT be rendered
      expect(find.byType(PulseIndicator), findsNothing);

      // "Verificar Integridade" button should NOT be rendered
      expect(find.text('Verificar Integridade'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Error handling when verification fails
  // **Validates: Requirements 3.3**
  // ═══════════════════════════════════════════════════════════════════════════

  group('Error handling when verification fails', () {
    testWidgets('displays error message when checkSchemaIntegrity throws', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockRepo = MockSuperAdminRepository();
      when(
        () => mockRepo.checkSchemaIntegrity(_testOrgId),
      ).thenThrow(Exception('Network timeout'));

      await tester.pumpWidget(_buildTestWidget(repo: mockRepo));
      await _pumpUntilFound(tester, find.text('Verificar Integridade'));

      // Tap the "Verificar Integridade" button
      final buttonFinder = find.text('Verificar Integridade');
      expect(buttonFinder, findsOneWidget);
      await tester.tap(buttonFinder);
      await tester.pump(); // Process the tap
      await tester.pump(const Duration(milliseconds: 100)); // Allow async

      // Error message should be displayed
      expect(
        find.textContaining('Falha na verificação'),
        findsOneWidget,
        reason: 'Error message should be shown when check fails',
      );
      expect(
        find.textContaining('Network timeout'),
        findsOneWidget,
        reason: 'Error message should contain the exception details',
      );
    });
  });
}
