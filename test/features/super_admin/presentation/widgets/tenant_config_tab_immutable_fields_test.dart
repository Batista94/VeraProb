import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/features/super_admin/application/tenant_health_view.dart';
import 'package:veraprob/features/super_admin/application/update_organization_quota_handler.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/features/super_admin/domain/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/locked_field_tile.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_config_tab.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ─── Mocks (same pattern from preservation test) ────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockUpdateQuotaHandler extends Mock
    implements UpdateOrganizationQuotaHandler {}

// ─── Test Helpers ───────────────────────────────────────────────────────────

/// Creates a [TenantHealthView] with sensible defaults for testing.
/// Extended with optional [cnpj] and [createdAt] params for immutable fields.
TenantHealthView _makeTenant({
  String id = 'test-org-id',
  String name = 'Test Org',
  OrgStatus status = OrgStatus.active,
  int? toolCostCents = 10000,
  int? billingDay,
  int maxVehicles = 10,
  String? cnpj,
  DateTime? createdAt,
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
    cnpj: cnpj,
    createdAt: createdAt,
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

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // Task 6.2 — Widget tests for immutable section in TenantConfigTab
  // **Validates: Requirements 2.1, 2.2, 2.9, 4.1, 4.2, 4.3, 4.4, 4.5,
  //              5.3, 6.4, 6.5**
  // ═══════════════════════════════════════════════════════════════════════════

  group('TenantConfigTab — Immutable Identity Section (Task 6.2)', () {
    testWidgets('1. Section "Identidade Imutável" text appears', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant();
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      expect(
        find.text('Identidade Imutável'),
        findsOneWidget,
        reason: 'Section title "Identidade Imutável" must appear in the tab',
      );
    });

    testWidgets('2. Slug LockedFieldTile shows tenant id value', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant(id: 'my-unique-slug-id');
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Verify the Slug LockedFieldTile exists
      final slugTile = find.widgetWithText(LockedFieldTile, 'Slug');
      expect(
        slugTile,
        findsOneWidget,
        reason: 'A LockedFieldTile with label "Slug" must exist',
      );

      // Verify the tenant id value is displayed
      expect(
        find.text('my-unique-slug-id'),
        findsOneWidget,
        reason: 'The tenant id value must be displayed in the Slug tile',
      );
    });

    testWidgets('3. CNPJ LockedFieldTile shows cnpj value when non-null', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant(cnpj: '12.345.678/0001-90');
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Verify the CNPJ LockedFieldTile exists
      final cnpjTile = find.widgetWithText(LockedFieldTile, 'CNPJ');
      expect(
        cnpjTile,
        findsOneWidget,
        reason: 'A LockedFieldTile with label "CNPJ" must exist',
      );

      // Verify the cnpj value is displayed
      expect(
        find.text('12.345.678/0001-90'),
        findsOneWidget,
        reason: 'The CNPJ value must be displayed in the CNPJ tile',
      );
    });

    testWidgets('4. "Não informado" placeholder shown when cnpj is null', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant(cnpj: null);
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Verify the CNPJ LockedFieldTile exists
      final cnpjTile = find.widgetWithText(LockedFieldTile, 'CNPJ');
      expect(
        cnpjTile,
        findsOneWidget,
        reason: 'A LockedFieldTile with label "CNPJ" must exist even when null',
      );

      // Verify the placeholder is shown
      expect(
        find.text('Não informado'),
        findsOneWidget,
        reason:
            'When cnpj is null, the placeholder "Não informado" must be shown',
      );
    });

    testWidgets(
      '5. Data de Criação shows formatted date (dd/MM/yyyy HH:mm) when non-null',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tenant = _makeTenant(createdAt: DateTime(2025, 3, 15, 14, 30));
        await tester.pumpWidget(_buildTestWidget(tenant));
        await tester.pumpAndSettle();

        // Verify the Data de Criação LockedFieldTile exists
        final dateTile = find.widgetWithText(
          LockedFieldTile,
          'Data de Criação',
        );
        expect(
          dateTile,
          findsOneWidget,
          reason: 'A LockedFieldTile with label "Data de Criação" must exist',
        );

        // Verify the formatted date is displayed
        expect(
          find.text('15/03/2025 14:30'),
          findsOneWidget,
          reason: 'The createdAt date must be formatted as dd/MM/yyyy HH:mm',
        );
      },
    );

    testWidgets(
      '6. "Não disponível" placeholder shown when createdAt is null',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tenant = _makeTenant(createdAt: null);
        await tester.pumpWidget(_buildTestWidget(tenant));
        await tester.pumpAndSettle();

        // Verify the Data de Criação LockedFieldTile exists
        final dateTile = find.widgetWithText(
          LockedFieldTile,
          'Data de Criação',
        );
        expect(
          dateTile,
          findsOneWidget,
          reason:
              'A LockedFieldTile with label "Data de Criação" must exist '
              'even when createdAt is null',
        );

        // Verify the placeholder is shown
        expect(
          find.text('Não disponível'),
          findsOneWidget,
          reason:
              'When createdAt is null, the placeholder "Não disponível" '
              'must be shown',
        );
      },
    );

    testWidgets('7. Divider exists between immutable and editable sections', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant();
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Verify a Divider widget exists in the tree
      expect(
        find.byType(Divider),
        findsAtLeastNWidgets(1),
        reason:
            'A Divider must exist between the immutable and editable sections',
      );
    });

    testWidgets('8. Razão Social TextFormField still exists and is editable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant();
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Find the Razão Social field by its label text
      final razaoSocialField = find.ancestor(
        of: find.text('Razão Social'),
        matching: find.byType(TextFormField),
      );
      expect(
        razaoSocialField,
        findsOneWidget,
        reason:
            'Razão Social TextFormField must still exist in the editable section',
      );

      // Verify it is editable by entering text
      await tester.enterText(razaoSocialField, 'Nova Razão Social');
      await tester.pumpAndSettle();

      expect(
        find.text('Nova Razão Social'),
        findsOneWidget,
        reason: 'Razão Social field must accept text input (editable)',
      );
    });

    testWidgets('9. Nome Fantasia TextFormField still exists and is editable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenant = _makeTenant();
      await tester.pumpWidget(_buildTestWidget(tenant));
      await tester.pumpAndSettle();

      // Find the Nome Fantasia field by its label text
      final nomeFantasiaField = find.ancestor(
        of: find.text('Nome Fantasia'),
        matching: find.byType(TextFormField),
      );
      expect(
        nomeFantasiaField,
        findsOneWidget,
        reason:
            'Nome Fantasia TextFormField must still exist in the editable section',
      );

      // Verify it is editable by entering text
      await tester.enterText(nomeFantasiaField, 'Novo Nome Fantasia');
      await tester.pumpAndSettle();

      expect(
        find.text('Novo Nome Fantasia'),
        findsOneWidget,
        reason: 'Nome Fantasia field must accept text input (editable)',
      );
    });
  });
}
