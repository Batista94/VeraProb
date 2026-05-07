import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/update_organization_quota_handler.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_config_tab.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ─── Mocks (reused pattern from bug conditions tests) ───────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockUpdateQuotaHandler extends Mock
    implements UpdateOrganizationQuotaHandler {}

// ─── Test Helpers (reused from bug conditions tests) ────────────────────────

/// Creates a [TenantHealthView] with sensible defaults for testing.
TenantHealthView _makeTenant({
  String id = 'test-org-id',
  String name = 'Test Org',
  OrgStatus status = OrgStatus.active,
  int? toolCostCents = 10000,
  int? billingDay,
  int maxVehicles = 10,
}) {
  return TenantHealthView(
    id: id,
    name: name,
    status: status,
    maxVehicles: maxVehicles,
    maxActiveContracts: 5,
    activeContractCount: 2,
    openCriticalAlertCount: 0,
    toolCostCents: toolCostCents,
    billingDay: billingDay,
  );
}

/// Wraps [TenantConfigTab] in a [MaterialApp] + [ProviderScope] with
/// all required provider overrides so the widget can render in isolation.
Widget _buildTestWidget(
  TenantHealthView tenant, {
  MockSuperAdminRepository? repo,
  MockUpdateQuotaHandler? handler,
}) {
  final mockRepo = repo ?? MockSuperAdminRepository();
  final mockHandler = handler ?? MockUpdateQuotaHandler();

  return ProviderScope(
    overrides: [
      superAdminRepositoryProvider.overrideWithValue(mockRepo),
      updateOrganizationQuotaHandlerProvider.overrideWithValue(mockHandler),
      tenantHealthSnapshotProvider.overrideWith(
        (ref) async => <TenantHealthView>[],
      ),
      authStateProvider.overrideWith((ref) => const Stream<Never>.empty()),
      currentSessionIdProvider.overrideWithValue('test-session'),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 1200,
          child: TenantConfigTab(tenant: tenant),
        ),
      ),
    ),
  );
}

/// Makes the form dirty by toggling the 'Lacre' capability switch once.
/// This triggers `setState` and changes `_capabilities`, which makes
/// `_isDirty` return true via the `_capabilities != t.capabilities` check.
///
/// `tester.enterText` updates the TextEditingController but does NOT trigger
/// the `onChanged` callback on TextFormField, so `setState` is never called.
Future<void> _makeFormDirtyViaCapabilityToggle(WidgetTester tester) async {
  final lacreSwitch = find.widgetWithText(SwitchListTile, 'Lacre');
  await tester.ensureVisible(lacreSwitch);
  await tester.pumpAndSettle();
  await tester.tap(lacreSwitch);
  await tester.pumpAndSettle();
}

/// Finds the save button by its label text.
///
/// `FilledButton.icon()` creates a `_FilledButtonWithIcon` (private subclass)
/// which is NOT matched by `find.byType(FilledButton)`. We use text-based
/// lookup instead.
Finder _findSaveButton() => find.text('Salvar Alteracoes');

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Preservation C₁ — billingDay accepts valid values (PBT)
  // **Validates: Requirements 3.1**
  //
  // On UNFIXED code: no validator exists on billingDay field, so valid values
  // produce no error (trivially passes).
  // After fix: validator returns null for valid values (1–28 and empty),
  // so no error is shown (still passes).
  // ═══════════════════════════════════════════════════════════════════════════

  group('Preservation C₁ — billingDay accepts valid values (PBT)', () {
    testWidgets(
      'Property: for all integers n in 1–28, billingDay shows no error',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tenant = _makeTenant();
        await tester.pumpWidget(_buildTestWidget(tenant));
        await tester.pumpAndSettle();

        // Generate all valid billingDay values 1–28 plus random samples
        final random = Random(42); // deterministic seed
        final validValues = <String>[
          // All boundary and interior values
          for (var n = 1; n <= 28; n++) n.toString(),
          // Random valid values for extra coverage
          for (var i = 0; i < 10; i++) (random.nextInt(28) + 1).toString(),
        ];

        // Find the billingDay field
        final billingDayField = find.ancestor(
          of: find.text('Dia de Faturamento (1-28)'),
          matching: find.byType(TextFormField),
        );
        expect(
          billingDayField,
          findsOneWidget,
          reason: 'billingDay TextFormField must exist',
        );

        for (final validValue in validValues) {
          // Enter the valid value
          await tester.enterText(billingDayField, validValue);
          await tester.pumpAndSettle();

          // Assert NO error message appears for valid values
          // On UNFIXED code: no validator → no error (passes)
          // After fix: validator returns null for 1–28 → no error (passes)
          expect(
            find.text('Dia inválido (1-28)'),
            findsNothing,
            reason:
                'Preservation C₁: billingDay="$validValue" is valid (1–28), '
                'should show no error',
          );
        }
      },
    );

    testWidgets('billingDay empty string shows no error', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant();
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Find the billingDay field
      final billingDayField = find.ancestor(
        of: find.text('Dia de Faturamento (1-28)'),
        matching: find.byType(TextFormField),
      );
      expect(billingDayField, findsOneWidget);

      // Enter empty string (clear the field)
      await tester.enterText(billingDayField, '');
      await tester.pumpAndSettle();

      // Assert NO error message for empty (optional field)
      // On UNFIXED code: no validator → no error (passes)
      // After fix: validator returns null for empty → no error (passes)
      expect(
        find.text('Dia inválido (1-28)'),
        findsNothing,
        reason:
            'Preservation C₁: empty billingDay is valid (optional field), '
            'should show no error',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Preservation C₂ — active tenant save button visible when dirty
  // **Validates: Requirements 3.2**
  //
  // On UNFIXED code: `if (_isDirty)` shows save button for any dirty form,
  // including active tenants (passes).
  // After fix: `if (_isDirty && !widget.tenant.isArchived)` still shows
  // save button for active (non-archived) tenants (still passes).
  // ═══════════════════════════════════════════════════════════════════════════

  group('Preservation C₂ — active tenant save button visible when dirty', () {
    testWidgets('active tenant with dirty form shows save button', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Create an ACTIVE tenant
      final tenant = _makeTenant(
        status: OrgStatus.active,
        toolCostCents: 10000,
      );
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Verify save button is NOT visible before making form dirty
      expect(
        _findSaveButton(),
        findsNothing,
        reason: 'Save button should not appear on clean form',
      );

      // Make the form dirty via capability toggle
      await _makeFormDirtyViaCapabilityToggle(tester);

      // Assert save button IS visible for active tenant with dirty form
      // On UNFIXED code: `if (_isDirty)` → visible (passes)
      // After fix: `if (_isDirty && !widget.tenant.isArchived)` → visible
      // because isArchived is false (still passes)
      expect(
        _findSaveButton(),
        findsOneWidget,
        reason:
            'Preservation C₂: active tenant with dirty form must show '
            'save button',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Preservation C₃ — save button enabled when form valid
  // **Validates: Requirements 3.3**
  //
  // On UNFIXED code: `onPressed: _save` is unconditional, so it's always
  // non-null when the button is visible (passes).
  // After fix: `onPressed: _isFormValid ? _save : null`, and since the form
  // is valid, onPressed is _save (still passes).
  // ═══════════════════════════════════════════════════════════════════════════

  group('Preservation C₃ — save button enabled when form valid', () {
    testWidgets(
      'valid form on active tenant has save button enabled (onPressed != null)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Active tenant with valid cost (100.00) and no billingDay (optional)
        final tenant = _makeTenant(
          status: OrgStatus.active,
          toolCostCents: 10000, // 100.00
          maxVehicles: 10,
        );
        await tester.pumpWidget(_buildTestWidget(tenant));
        await tester.pumpAndSettle();

        // Make the form dirty via capability toggle
        await _makeFormDirtyViaCapabilityToggle(tester);

        // Save button must be visible
        final saveButton = _findSaveButton();
        expect(
          saveButton,
          findsOneWidget,
          reason: 'Save button must be visible when form is dirty',
        );

        // Find the actual button widget
        final buttonFinder = find.ancestor(
          of: saveButton,
          matching: find.bySubtype<ButtonStyleButton>(),
        );
        expect(buttonFinder, findsOneWidget);
        final button = tester.widget<ButtonStyleButton>(buttonFinder);

        // Assert onPressed is NOT null (button is enabled)
        // On UNFIXED code: onPressed is always _save (passes)
        // After fix: _isFormValid is true (valid cost, no billingDay) →
        // onPressed is _save (still passes)
        expect(
          button.onPressed,
          isNotNull,
          reason:
              'Preservation C₃: valid form on active tenant must have '
              'save button enabled (onPressed != null)',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Preservation C₄ — existing tenantHealthSnapshotProvider invalidation
  // **Validates: Requirements 3.4**
  //
  // On UNFIXED code: archive/unarchive calls
  // ref.invalidate(tenantHealthSnapshotProvider). This test verifies the
  // provider exists and can be overridden/invalidated in a ProviderContainer.
  // After fix: tenantHealthSnapshotProvider is still invalidated (unchanged).
  // ═══════════════════════════════════════════════════════════════════════════

  group('Preservation C₄ — tenantHealthSnapshotProvider invalidation', () {
    test('tenantHealthSnapshotProvider exists and can be read/invalidated', () {
      var fetchCount = 0;
      final container = ProviderContainer(
        overrides: [
          tenantHealthSnapshotProvider.overrideWith((ref) async {
            fetchCount++;
            return <TenantHealthView>[_makeTenant(id: 'org-1', name: 'Org 1')];
          }),
        ],
      );
      addTearDown(container.dispose);

      // Read the provider to trigger the first fetch
      container.read(tenantHealthSnapshotProvider);
      expect(fetchCount, 1, reason: 'First read should trigger fetch');

      // Invalidate and re-read — this is the pattern used in _archiveOrg
      // and _unarchiveOrg on both unfixed and fixed code
      container.invalidate(tenantHealthSnapshotProvider);
      container.read(tenantHealthSnapshotProvider);
      expect(
        fetchCount,
        2,
        reason:
            'Preservation C₄: invalidating tenantHealthSnapshotProvider '
            'must trigger a re-fetch (this is the existing behavior)',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Preservation existing validators — maxVehicles and cost
  // **Validates: Requirements 3.5, 3.6**
  //
  // These validators already exist on unfixed code. This test captures their
  // current behavior to ensure the fix doesn't regress them.
  // ═══════════════════════════════════════════════════════════════════════════

  group('Preservation existing validators — maxVehicles and cost', () {
    testWidgets('maxVehicles "0" shows "Mínimo: 1"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant(toolCostCents: 10000, maxVehicles: 10);
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Find the maxVehicles field
      final maxVehiclesField = find.ancestor(
        of: find.text('Max Veículos (Vazio=Ilimitado)'),
        matching: find.byType(TextFormField),
      );
      expect(maxVehiclesField, findsOneWidget);

      // Enter invalid value "0"
      await tester.enterText(maxVehiclesField, '0');
      await tester.pumpAndSettle();

      // Make form dirty to trigger validation display
      await _makeFormDirtyViaCapabilityToggle(tester);

      // Assert existing validator error
      expect(
        find.text('Mínimo: 1'),
        findsOneWidget,
        reason: 'Preservation: maxVehicles "0" must show "Mínimo: 1" error',
      );
    });

    testWidgets('cost "" shows "Obrigatório"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant(toolCostCents: 10000);
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Find the cost field
      final costField = find.ancestor(
        of: find.text('Custo Ferramenta (R\$)'),
        matching: find.byType(TextFormField),
      );
      expect(costField, findsOneWidget);

      // Clear the cost field (enter empty string)
      await tester.enterText(costField, '');
      await tester.pumpAndSettle();

      // Make form dirty to trigger validation display
      await _makeFormDirtyViaCapabilityToggle(tester);

      // Assert existing validator error
      expect(
        find.text('Obrigatório'),
        findsOneWidget,
        reason: 'Preservation: cost "" must show "Obrigatório" error',
      );
    });

    testWidgets('cost "-1" shows "Valor inválido (≥ 0)"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant(toolCostCents: 10000);
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Find the cost field
      final costField = find.ancestor(
        of: find.text('Custo Ferramenta (R\$)'),
        matching: find.byType(TextFormField),
      );
      expect(costField, findsOneWidget);

      // Enter invalid cost "-1"
      await tester.enterText(costField, '-1');
      await tester.pumpAndSettle();

      // Make form dirty to trigger validation display
      await _makeFormDirtyViaCapabilityToggle(tester);

      // Assert existing validator error
      expect(
        find.text('Valor inválido (≥ 0)'),
        findsOneWidget,
        reason:
            'Preservation: cost "-1" must show "Valor inválido (≥ 0)" error',
      );
    });
  });
}
