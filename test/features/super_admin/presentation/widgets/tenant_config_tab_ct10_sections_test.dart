// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/update_organization_quota_handler.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_config_tab.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockUpdateQuotaHandler extends Mock
    implements UpdateOrganizationQuotaHandler {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

TenantHealthView _makeTenant({
  String id = 'test-org-id',
  String name = 'Test Org',
  OrgStatus status = OrgStatus.active,
  int? toolCostCents = 10000,
  int clockDriftToleranceS = 300,
  int dataRetentionDays = 1825,
  int connectionPoolLimit = 60,
  int storageQuotaGb = 100,
  List<String> allowedDomains = const [],
}) {
  return TenantHealthView(
    id: id,
    name: name,
    status: status,
    maxVehicles: 10,
    maxActiveContracts: 5,
    activeContractCount: 2,
    openCriticalAlertCount: 0,
    toolCostCents: toolCostCents,
    clockDriftToleranceS: clockDriftToleranceS,
    dataRetentionDays: dataRetentionDays,
    connectionPoolLimit: connectionPoolLimit,
    storageQuotaGb: storageQuotaGb,
    allowedDomains: allowedDomains,
  );
}

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
          height: 1400,
          child: TenantConfigTab(tenant: tenant),
        ),
      ),
    ),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() {
    registerFallbackValue(
      const UpdateOrganizationQuotaCommand(
        organizationId: 'fallback-org',
        newPlanType: 'starter',
        superAdminUserId: 'sa-fallback',
        reason: 'fallback reason test',
        sessionId: '',
        toolCostCents: 10000,
      ),
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // T8 — Seções Motor Forense, Compliance, Infraestrutura renderizam
  // ═══════════════════════════════════════════════════════════════════════════

  group('CT10 — seções novas (T8)', () {
    testWidgets('seção "Motor Forense" aparece na aba Config', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWidget(_makeTenant()));
      await tester.pumpAndSettle();

      expect(
        find.text('Motor Forense'),
        findsOneWidget,
        reason:
            'Seção "Motor Forense" deve aparecer na aba Configuração (CT10)',
      );
    });

    testWidgets('seção "Compliance" aparece na aba Config', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWidget(_makeTenant()));
      await tester.pumpAndSettle();

      expect(
        find.text('Compliance'),
        findsOneWidget,
        reason: 'Seção "Compliance" deve aparecer na aba Configuração (CT10)',
      );
    });

    testWidgets('seção "Infraestrutura" aparece na aba Config', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWidget(_makeTenant()));
      await tester.pumpAndSettle();

      expect(
        find.text('Infraestrutura'),
        findsOneWidget,
        reason:
            'Seção "Infraestrutura" deve aparecer na aba Configuração (CT10)',
      );
    });

    testWidgets('campo Tolerância Clock Drift inicializa com valor do tenant', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(_makeTenant(clockDriftToleranceS: 600)),
      );
      await tester.pumpAndSettle();

      // O campo deve conter o valor do tenant
      final field = find.byKey(const Key('clock_drift_tolerance_s_field'));
      expect(field, findsOneWidget);
      expect((tester.widget<TextFormField>(field).controller)?.text, '600');
    });

    testWidgets('campo Retenção de Dados inicializa com valor do tenant', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(_makeTenant(dataRetentionDays: 3650)),
      );
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('data_retention_days_field'));
      expect(field, findsOneWidget);
      expect((tester.widget<TextFormField>(field).controller)?.text, '3650');
    });

    testWidgets('campo Connection Pool Limit inicializa com valor do tenant', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(_makeTenant(connectionPoolLimit: 100)),
      );
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('connection_pool_limit_field'));
      expect(field, findsOneWidget);
      expect((tester.widget<TextFormField>(field).controller)?.text, '100');
    });

    testWidgets('campo Storage Quota inicializa com valor do tenant', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(_makeTenant(storageQuotaGb: 500)),
      );
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('storage_quota_gb_field'));
      expect(field, findsOneWidget);
      expect((tester.widget<TextFormField>(field).controller)?.text, '500');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // T9 — Domínios Permitidos na aba Configuração
  // ═══════════════════════════════════════════════════════════════════════════

  group('CT10 — Domínios Permitidos na aba Config (T9)', () {
    testWidgets('seção "Domínios Permitidos" aparece na aba Config', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWidget(_makeTenant()));
      await tester.pumpAndSettle();

      expect(
        find.text('Domínios Permitidos'),
        findsOneWidget,
        reason:
            'Seção Domínios Permitidos deve estar na aba Configuração (CT10/1A)',
      );
    });

    testWidgets('chips de domínio existentes são renderizados', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(
          _makeTenant(allowedDomains: ['viacao.com.br', 'exemplo.com']),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('viacao.com.br'), findsOneWidget);
      expect(find.text('exemplo.com'), findsOneWidget);
    });

    testWidgets('mensagem de aviso quando nenhum domínio configurado', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestWidget(_makeTenant(allowedDomains: [])),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('qualquer e-mail pode fazer login'),
        findsOneWidget,
      );
    });

    testWidgets('campo de input de domínio existe e é editável', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWidget(_makeTenant()));
      await tester.pumpAndSettle();

      final input = find.byKey(const Key('domain_input_field'));
      expect(input, findsOneWidget);

      await tester.enterText(input, 'novodominio.com.br');
      await tester.pumpAndSettle();
      expect(find.text('novodominio.com.br'), findsWidgets);
    });

    testWidgets('botão Adicionar domínio está presente', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWidget(_makeTenant()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('domain_add_button')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // T10 — Campos desabilitados quando org está arquivada
  // ═══════════════════════════════════════════════════════════════════════════

  group('CT10 — campos disabled quando org arquivada (T10)', () {
    testWidgets('campo clock drift desabilitado quando arquivado', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final archived = _makeTenant(status: OrgStatus.archived);
      await tester.pumpWidget(_buildTestWidget(archived));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('clock_drift_tolerance_s_field')),
      );
      expect(
        field.enabled,
        isFalse,
        reason: 'clock drift field deve ser disabled quando org está arquivada',
      );
    });

    testWidgets('campo data retention desabilitado quando arquivado', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final archived = _makeTenant(status: OrgStatus.archived);
      await tester.pumpWidget(_buildTestWidget(archived));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('data_retention_days_field')),
      );
      expect(field.enabled, isFalse);
    });

    testWidgets('campo connection pool desabilitado quando arquivado', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final archived = _makeTenant(status: OrgStatus.archived);
      await tester.pumpWidget(_buildTestWidget(archived));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('connection_pool_limit_field')),
      );
      expect(field.enabled, isFalse);
    });

    testWidgets('campo storage quota desabilitado quando arquivado', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final archived = _makeTenant(status: OrgStatus.archived);
      await tester.pumpWidget(_buildTestWidget(archived));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('storage_quota_gb_field')),
      );
      expect(field.enabled, isFalse);
    });

    testWidgets('botão adicionar domínio ausente quando arquivado', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final archived = _makeTenant(status: OrgStatus.archived);
      await tester.pumpWidget(_buildTestWidget(archived));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('domain_add_button')),
        findsNothing,
        reason: 'botão de adicionar domínio não deve aparecer quando arquivado',
      );
    });
  });
}
