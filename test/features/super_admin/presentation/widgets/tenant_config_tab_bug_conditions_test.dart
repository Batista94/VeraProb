import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/features/super_admin/application/archive_organization_handler.dart';
import 'package:veraprob/features/super_admin/application/tenant_health_view.dart';
import 'package:veraprob/features/super_admin/application/update_organization_quota_handler.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/features/super_admin/domain/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_config_tab.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
// NOTE: C₄ tests are in a separate file (tenant_config_tab_c4_bug_conditions_test.dart)
// because they reference tenantDetailProvider/tenantsListProvider which don't exist
// on unfixed code. Keeping them here would cause compile errors that block C₁–C₃.
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockUpdateQuotaHandler extends Mock
    implements UpdateOrganizationQuotaHandler {}

class MockArchiveHandler extends Mock implements ArchiveOrganizationHandler {}

// ─── Test Helpers ───────────────────────────────────────────────────────────

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
/// This is the reliable way to make the form dirty in widget tests because
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

// ─── Bug Condition Predicates (from bugfix.md) ──────────────────────────────

/// C₁: billingDay field has a non-empty value outside 1–28.
bool isBugConditionC1(String value) {
  if (value.isEmpty) return false;
  final n = int.tryParse(value);
  return n == null || n < 1 || n > 28;
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // C₁ — billingDay validator rejects invalid values (PBT)
  // **Validates: Requirements 1.1**
  //
  // Bug condition: billingDay TextFormField has NO validator callback.
  // Expected behavior (after fix): validator returns 'Dia inválido (1-28)'
  // for any non-empty value outside 1–28 or non-numeric.
  //
  // On UNFIXED code: test FAILS because no validator exists.
  // ═══════════════════════════════════════════════════════════════════════════

  group('C₁ — billingDay validator rejects invalid values (PBT)', () {
    testWidgets(
      'Property: for all invalid billingDay values, validator shows error',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tenant = _makeTenant();
        await tester.pumpWidget(_buildTestWidget(tenant));
        await tester.pumpAndSettle();

        // Generate invalid billingDay values using PBT approach
        final random = Random(42); // deterministic seed
        final invalidValues = <String>[
          // Boundary values outside 1–28
          '0', '29', '-1', '100', '-100',
          // Non-numeric strings
          'abc', '1.5', '3e2', ' ', 'null',
          // Random integers outside 1–28
          for (var i = 0; i < 20; i++)
            (random.nextInt(1000) + 29).toString(), // 29–1028
          for (var i = 0; i < 10; i++)
            (-random.nextInt(100) - 1).toString(), // -1 to -100
        ];

        // Verify all generated values satisfy the bug condition predicate
        for (final v in invalidValues) {
          assert(
            isBugConditionC1(v),
            'Expected isBugConditionC1("$v") == true',
          );
        }

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

        // Test each invalid value
        for (final invalidValue in invalidValues) {
          // Clear and enter the invalid value
          await tester.enterText(billingDayField, invalidValue);
          await tester.pump();

          // Trigger validation by interacting with another field then back
          // AutovalidateMode.onUserInteraction should trigger validation
          await tester.pumpAndSettle();

          // Assert the validator error message appears
          // On UNFIXED code: no validator exists, so this FAILS
          expect(
            find.text('Dia inválido (1-28)'),
            findsOneWidget,
            reason:
                'C₁ counterexample: billingDay="$invalidValue" should show '
                '"Dia inválido (1-28)" but no validator exists on unfixed code',
          );
        }
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // C₂ — archive guard hides save button (deterministic)
  // **Validates: Requirements 1.2**
  //
  // Bug condition: save button visible on archived tenant with dirty form.
  // Expected behavior (after fix): save button NOT rendered when isArchived.
  //
  // On UNFIXED code: test FAILS because `if (_isDirty)` has no archive check.
  // ═══════════════════════════════════════════════════════════════════════════

  group('C₂ — archive guard hides save button', () {
    testWidgets('archived tenant with dirty form should NOT show save button', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Create an ARCHIVED tenant
      final tenant = _makeTenant(
        status: OrgStatus.archived,
        toolCostCents: 10000,
      );
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Make the form dirty by toggling a capability switch.
      // This reliably triggers setState and makes _isDirty true.
      await _makeFormDirtyViaCapabilityToggle(tester);

      // Assert save button text is NOT rendered.
      // On UNFIXED code: `if (_isDirty)` has no `!widget.tenant.isArchived`
      // guard, so the save button IS visible — test FAILS.
      // On FIXED code: `if (_isDirty && !widget.tenant.isArchived)` hides it.
      expect(
        _findSaveButton(),
        findsNothing,
        reason:
            'C₂ counterexample: save button visible on archived tenant — '
            '`if (_isDirty)` has no archive check',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // C₃ — save button disabled when form invalid (PBT)
  // **Validates: Requirements 1.3**
  //
  // Bug condition: save button enabled (onPressed != null) despite invalid form
  // on active tenant with dirty form.
  // Expected behavior (after fix): onPressed is null when form invalid.
  //
  // On UNFIXED code: test FAILS because `onPressed: _save` is unconditional.
  // ═══════════════════════════════════════════════════════════════════════════

  group('C₃ — save button disabled when form invalid (PBT)', () {
    testWidgets(
      'Property: for all invalid form states, save button onPressed is null',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Active tenant with valid initial cost so we can make it dirty
        final tenant = _makeTenant(
          status: OrgStatus.active,
          toolCostCents: 10000, // 100.00
        );
        await tester.pumpWidget(_buildTestWidget(tenant));
        await tester.pumpAndSettle();

        // Generate invalid cost values using PBT approach
        final invalidCostValues = <String>[
          '-1',
          '-0.01',
          '-100',
          '-999.99',
          'abc',
          'NaN',
        ];

        for (final invalidCost in invalidCostValues) {
          // Enter invalid cost to make form invalid AND dirty
          final costField = find.ancestor(
            of: find.text('Custo Ferramenta (R\$)'),
            matching: find.byType(TextFormField),
          );
          expect(costField, findsOneWidget);
          await tester.enterText(costField, invalidCost);
          await tester.pumpAndSettle();

          // Make form dirty via capability toggle (this triggers setState
          // and ensures _isDirty returns true)
          await _makeFormDirtyViaCapabilityToggle(tester);

          // The form is now dirty (capability changed) and invalid (cost is bad)
          // Save button MUST be rendered (because _isDirty is true on unfixed code)
          final saveButton = _findSaveButton();
          expect(
            saveButton,
            findsOneWidget,
            reason:
                'Save button must be visible when form is dirty '
                '(cost="$invalidCost")',
          );

          // Find the actual button widget by walking up from the Text widget.
          // FilledButton.icon creates _FilledButtonWithIcon (private subclass),
          // so we find the nearest ButtonStyleButton ancestor.
          final buttonFinder = find.ancestor(
            of: saveButton,
            matching: find.bySubtype<ButtonStyleButton>(),
          );
          expect(buttonFinder, findsOneWidget);
          final button = tester.widget<ButtonStyleButton>(buttonFinder);

          // Check that onPressed is null (disabled) — this is the expected behavior
          // On UNFIXED code: onPressed is _save (not null) — test FAILS
          expect(
            button.onPressed,
            isNull,
            reason:
                'C₃ counterexample: cost="$invalidCost" makes form invalid, '
                'but onPressed is _save (not null) — unconditional on unfixed code',
          );

          // Reset: toggle capability back and restore cost
          await _makeFormDirtyViaCapabilityToggle(tester);
          await tester.enterText(costField, '100.00');
          await tester.pumpAndSettle();
        }
      },
    );
  });

  // C₄ tests are in a separate file: tenant_config_tab_c4_bug_conditions_test.dart
  // They reference tenantDetailProvider/tenantsListProvider which don't exist on
  // unfixed code — keeping them here would block C₁–C₃ from compiling.
}
