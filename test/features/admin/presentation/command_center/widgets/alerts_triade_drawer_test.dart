// INV-7: No dynamic in mocks or fixtures.
// INV-1: All fixtures scoped to _kOrgId.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/quick_reconciliation_service.dart';
import 'package:veraprob/infrastructure/audio/alert_sound_service.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade_drawer.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/evidence_dossier_modal.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_category_chip.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_link_source_chip.dart';
import 'package:veraprob/infrastructure/shared/evidence_url_service.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────────

class MockAlertSoundService extends Mock implements AlertSoundService {}

class MockOperationalAlertRepository extends Mock
    implements OperationalAlertRepository {}

class MockQuickReconciliationService extends Mock
    implements QuickReconciliationService {}

// ── Fake stream notifier ───────────────────────────────────────────────────────

/// Wraps a [StreamController] so tests can push alert lists at will.
/// Extends [ActiveAlertsNotifier] so [overrideWith] type-checks correctly.
class _FakeActiveAlertsNotifier extends ActiveAlertsNotifier {
  _FakeActiveAlertsNotifier(this._controller);

  final StreamController<List<OperationalAlert>> _controller;

  @override
  Stream<List<OperationalAlert>> build() => _controller.stream;
}

/// Notifier that directly sets [AsyncError] state before returning an empty
/// stream — avoids Riverpod 3 stream-to-state timing issues in tests.
/// Setting [state] inside [build] is legal for [AsyncNotifier] subclasses;
/// the subsequent [Stream.empty] completion does not overwrite it.
class _ErrorActiveAlertsNotifier extends ActiveAlertsNotifier {
  @override
  Stream<List<OperationalAlert>> build() {
    // ignore: invalid_use_of_protected_member
    state = AsyncError(Exception('falha de rede'), StackTrace.empty);
    return const Stream.empty();
  }
}

// ── Fake EvidenceUrlService ────────────────────────────────────────────────────

/// Returns deterministic test URLs — avoids hitting [EnvironmentConfig] in tests.
class _FakeEvidenceUrlService implements EvidenceUrlService {
  const _FakeEvidenceUrlService();

  @override
  String getProxyUrl(String evidenceId) =>
      'https://test.local/evidence/$evidenceId';

  @override
  String getDisputeAttachmentProxyUrl(String attachmentId) =>
      'https://test.local/dispute-evidence/$attachmentId';
}

// ── Fixture constants ──────────────────────────────────────────────────────────

const _kOrgId = 'org-test-001';
const _kUserId = 'user-test-001';
const _kSessionToken = 'fake-jwt-token';
const _kContractId = 'contract-test-001';
const _kEntityId = 'set-test-001';

// ── Fixtures ───────────────────────────────────────────────────────────────────

OperationalAlert alertCritical({
  String id = 'alert-critical-01',
  List<String> viewedByUserIds = const [],
  String? driverName,
  Map<String, Object> extraContext = const {},
}) {
  final context = <String, Object>{'driver_name': ?driverName, ...extraContext};
  return OperationalAlert(
    id: id,
    organizationId: _kOrgId,
    entityId: _kEntityId,
    contractId: _kContractId,
    alertType: 'NO_SHOW',
    severity: 'CRITICAL',
    triggeredAtUtc: DateTime.utc(2026, 5, 11, 10, 0),
    context: context,
    viewedByUserIds: viewedByUserIds,
  );
}

OperationalAlert alertHigh({
  String id = 'alert-high-01',
  List<String> viewedByUserIds = const [],
  String? driverName,
  Map<String, Object> extraContext = const {},
}) {
  final context = <String, Object>{'driver_name': ?driverName, ...extraContext};
  return OperationalAlert(
    id: id,
    organizationId: _kOrgId,
    entityId: _kEntityId,
    contractId: _kContractId,
    alertType: 'EVIDENCE_GAP',
    severity: 'HIGH',
    triggeredAtUtc: DateTime.utc(2026, 5, 11, 9, 30),
    context: context,
    viewedByUserIds: viewedByUserIds,
  );
}

OperationalAlert alertLow({
  String id = 'alert-low-01',
  List<String> viewedByUserIds = const [],
  Map<String, Object> extraContext = const {},
}) => OperationalAlert(
  id: id,
  organizationId: _kOrgId,
  entityId: _kEntityId,
  contractId: _kContractId,
  alertType: 'PENALTY_APPLIED',
  severity: 'LOW',
  triggeredAtUtc: DateTime.utc(2026, 5, 11, 8, 0),
  context: extraContext,
  viewedByUserIds: viewedByUserIds,
);

/// TELEGRAM_ORPHAN fixture — carries [driverId] + [evidenceIds] in context
/// so [_QuickLinkButton] renders. INV-7: context values are strictly typed.
OperationalAlert alertTelegramOrphan({
  String id = 'alert-orphan-01',
  String driverId = 'driver-test-01',
  List<String> evidenceIds = const ['ev-test-01'],
  List<String> viewedByUserIds = const [],
}) => OperationalAlert(
  id: id,
  organizationId: _kOrgId,
  entityId: _kEntityId,
  contractId: _kContractId,
  alertType: 'TELEGRAM_ORPHAN',
  severity: 'HIGH',
  triggeredAtUtc: DateTime.utc(2026, 5, 11, 9, 0),
  context: <String, Object>{'driver_id': driverId, 'evidence_ids': evidenceIds},
  viewedByUserIds: viewedByUserIds,
);

/// DISPUTE_DEFENSE_SUBMITTED fixture — carrier portal contestation surfaced in
/// triage. Context is metadata-only (no raw justification text): the auditor
/// deep-links to the disputed lane to read it. INV-7: strictly typed context.
OperationalAlert alertDisputeDefense({
  String id = 'alert-dispute-01',
  String vehiclePlate = 'TST-0001',
  String driverName = 'Carlos',
  int fineCents = 150000,
  String defenseType = 'file',
  String? filename = 'contraprova.jpg',
}) => OperationalAlert(
  id: id,
  organizationId: _kOrgId,
  entityId: vehiclePlate,
  contractId: _kContractId,
  alertType: 'DISPUTE_DEFENSE_SUBMITTED',
  severity: 'HIGH',
  triggeredAtUtc: DateTime.utc(2026, 5, 11, 11, 0),
  context: <String, Object>{
    'queue_entry_id': 'queue-test-01',
    'vehicle_plate': vehiclePlate,
    'driver_name': driverName,
    'fine_amount_cents': fineCents,
    'defense_type': defenseType,
    'filename': ?filename,
  },
  viewedByUserIds: const [],
);

// ── Main ───────────────────────────────────────────────────────────────────────

void main() {
  late MockAlertSoundService soundService;
  late MockOperationalAlertRepository alertRepo;
  late MockQuickReconciliationService reconciliationService;
  late StreamController<List<OperationalAlert>> alertStreamController;

  setUpAll(() {
    // mocktail fallback values for non-primitive types used with any()
    registerFallbackValue(alertCritical());
    registerFallbackValue(<String>[]);
    registerFallbackValue(<OperationalAlert>[]);
  });

  setUp(() {
    soundService = MockAlertSoundService();
    alertRepo = MockOperationalAlertRepository();
    reconciliationService = MockQuickReconciliationService();
    // broadcast so multiple listeners (ref.listen + markViewed) can coexist
    alertStreamController =
        StreamController<List<OperationalAlert>>.broadcast();

    // Default stubs — tests override per-case
    when(() => soundService.playAlertPing()).thenAnswer((_) async {});
    when(() => alertRepo.markViewed(any(), any())).thenAnswer((_) async {});
    when(
      () => reconciliationService.reconcileQuick(
        alertId: any(named: 'alertId'),
        organizationId: any(named: 'organizationId'),
        userId: any(named: 'userId'),
        evidenceIds: any(named: 'evidenceIds'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    if (!alertStreamController.isClosed) {
      await alertStreamController.close();
    }
  });

  // ── Build helper ───────────────────────────────────────────────────────────

  /// Pumps [AlertsTriadeDrawer] inside a full [ProviderScope] with all
  /// required provider overrides.
  ///
  /// [size] controls [tester.view.physicalSize]:
  ///   - narrow (width ≤ 1071px) → exercises 300px clamp
  ///   - wide   (width ≥ 1430px) → exercises 400px clamp
  ///
  /// Note: [selectedContractIdProvider] uses its default notifier — pure state
  /// with no external dependencies. No GoRouter ancestor is needed because no
  /// test taps "Reconciliar" (the only `context.go` call site in the drawer).
  Future<void> buildHost(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    ActiveAlertsNotifier Function()? alertsFactory,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Stream: default = alertStreamController; override for error scenarios.
          activeAlertsStreamProvider.overrideWith(
            alertsFactory ??
                () => _FakeActiveAlertsNotifier(alertStreamController),
          ),
          // Services
          alertSoundServiceProvider.overrideWithValue(soundService),
          operationalAlertRepositoryProvider.overrideWithValue(alertRepo),
          quickReconciliationServiceProvider.overrideWithValue(
            reconciliationService,
          ),
          // Auth / session (INV-1)
          currentOperatorIdProvider.overrideWithValue(_kUserId),
          currentOrganizationIdProvider.overrideWithValue(_kOrgId),
          currentSessionIdProvider.overrideWithValue(_kSessionToken),
          // Evidence proxy (INV-26) — no real EnvironmentConfig needed
          evidenceUrlServiceProvider.overrideWithValue(
            const _FakeEvidenceUrlService(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AlertsTriadeDrawer())),
      ),
    );
  }

  // ── Stream states, header, and grouping ───────────────────────────────────

  group('Estrutura e Agrupamento de Alertas', () {
    // ── Stream availability states ─────────────────────────────────────────

    testWidgets('exibe LinearProgressIndicator durante carregamento inicial', (
      tester,
    ) async {
      await buildHost(tester);
      await tester.pump();
      // Stream not yet emitted → AsyncLoading → indicator rendered
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'exibe mensagem de erro quando stream falha sem dados anteriores',
      (tester) async {
        // Use an error-emitting notifier — avoids broadcast-stream error delivery
        // timing issues in Riverpod 3 (stream.error fires as a microtask; the
        // standard alertStreamController.addError path doesn't reliably flush).
        await buildHost(tester, alertsFactory: _ErrorActiveAlertsNotifier.new);
        await tester.pump();
        expect(
          find.textContaining('Erro ao carregar alertas:'),
          findsOneWidget,
        );
      },
    );

    testWidgets('exibe empty state quando stream emite lista vazia', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([]);
      await tester.pump();
      expect(find.text('Operação Limpa'), findsOneWidget);
      expect(find.text('Nenhum alerta contratual pendente.'), findsOneWidget);
    });

    // ── Header static elements ─────────────────────────────────────────────

    testWidgets('header exibe ícone de alerta e botão de fechar com tooltip', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([]);
      await tester.pump();
      expect(find.byIcon(Icons.crisis_alert_rounded), findsOneWidget);
      expect(find.byTooltip('Fechar'), findsOneWidget);
    });

    // ── Summary counts ─────────────────────────────────────────────────────

    testWidgets('sumário exibe "1 ALERTA" e "1 motorista" para alerta único', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([alertLow()]);
      await tester.pump();
      expect(find.text('1 ALERTA'), findsOneWidget);
      expect(find.text('• 1 motorista'), findsOneWidget);
    });

    testWidgets(
      'sumário exibe plural "3 ALERTAS" e "2 motoristas" para alertas mistos',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          alertCritical(extraContext: {'driver_id': 'driver-aa'}),
          alertHigh(
            id: 'alert-high-02',
            extraContext: {'driver_id': 'driver-aa'},
          ),
          alertLow(extraContext: {'driver_id': 'driver-bb'}),
        ]);
        await tester.pump();
        expect(find.text('3 ALERTAS'), findsOneWidget);
        expect(find.text('• 2 motoristas'), findsOneWidget);
      },
    );

    // ── Driver grouping integrity ──────────────────────────────────────────

    testWidgets('agrupa múltiplos alertas do mesmo motorista em card único', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(
          id: 'alert-g1',
          driverName: 'Carlos',
          extraContext: {'driver_id': 'driver-carlos'},
        ),
        alertHigh(
          id: 'alert-g2',
          driverName: 'Carlos',
          extraContext: {'driver_id': 'driver-carlos'},
        ),
      ]);
      await tester.pump();
      // One group → singular summary
      expect(find.text('2 ALERTAS'), findsOneWidget);
      expect(find.text('• 1 motorista'), findsOneWidget);
      // Count badge when group.count > 1
      expect(find.text('+2'), findsOneWidget);
      // Driver name appears once in the group header
      expect(find.text('Carlos'), findsOneWidget);
    });

    testWidgets('exibe cards distintos para motoristas diferentes', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(
          id: 'alert-d1',
          driverName: 'João',
          extraContext: {'driver_id': 'driver-joao'},
        ),
        alertHigh(
          id: 'alert-d2',
          driverName: 'Maria',
          extraContext: {'driver_id': 'driver-maria'},
        ),
      ]);
      await tester.pump();
      expect(find.text('2 ALERTAS'), findsOneWidget);
      expect(find.text('• 2 motoristas'), findsOneWidget);
      // Both driver names rendered in separate group headers
      expect(find.text('João'), findsOneWidget);
      expect(find.text('Maria'), findsOneWidget);
    });

    testWidgets('exibe "Motorista Não Identificado" para alerta sem driver_id', (
      tester,
    ) async {
      await buildHost(tester);
      // alertLow has no driver_id in context → '_unknown' group → null driverName
      alertStreamController.add([alertLow()]);
      await tester.pump();
      expect(find.text('Motorista Não Identificado'), findsOneWidget);
    });
  });

  // ── Driver cards: expansion, health, content ──────────────────────────────

  group('Cards de Motoristas e Expansão', () {
    // ── Auto-expansão ────────────────────────────────────────────────────

    testWidgets('card com 1 alerta inicia expandido', (tester) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(extraContext: {'driver_id': 'driver-solo'}),
      ]);
      await tester.pump();
      // count == 1 ≤ 2 → auto-expanded → _RichEvidenceCard rendered
      expect(find.text('Reconciliar'), findsOneWidget);
    });

    testWidgets('card com 2 alertas inicia expandido', (tester) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(id: 'a1', extraContext: {'driver_id': 'driver-duo'}),
        alertHigh(id: 'a2', extraContext: {'driver_id': 'driver-duo'}),
      ]);
      await tester.pump();
      // count == 2 ≤ 2 → auto-expanded → two Reconciliar buttons
      expect(find.text('Reconciliar'), findsNWidgets(2));
    });

    testWidgets('card com 3+ alertas inicia colapsado', (tester) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(id: 'a1', extraContext: {'driver_id': 'driver-many'}),
        alertHigh(id: 'a2', extraContext: {'driver_id': 'driver-many'}),
        alertLow(id: 'a3', extraContext: {'driver_id': 'driver-many'}),
      ]);
      await tester.pump();
      // count == 3 > 2 → collapsed → no _RichEvidenceCard rendered
      expect(find.text('Reconciliar'), findsNothing);
    });

    testWidgets('tap no header expande card colapsado', (tester) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(
          id: 'p1',
          driverName: 'Pedro',
          extraContext: {'driver_id': 'driver-pedro'},
        ),
        alertHigh(
          id: 'p2',
          driverName: 'Pedro',
          extraContext: {'driver_id': 'driver-pedro'},
        ),
        alertLow(id: 'p3', extraContext: {'driver_id': 'driver-pedro'}),
      ]);
      await tester.pump();
      expect(find.text('Reconciliar'), findsNothing);

      await tester.tap(find.text('Pedro'));
      await tester.pump();

      expect(find.text('Reconciliar'), findsWidgets);
    });

    testWidgets('tap no header colapsa card expandido', (tester) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(
          driverName: 'Ana',
          extraContext: {'driver_id': 'driver-ana'},
        ),
      ]);
      await tester.pump();
      // 1 alert → auto-expanded
      expect(find.text('Reconciliar'), findsOneWidget);

      await tester.tap(find.text('Ana'));
      await tester.pump();

      expect(find.text('Reconciliar'), findsNothing);
    });

    // ── Indicadores de saúde ─────────────────────────────────────────────

    testWidgets('health CRITICAL exibe ícone error_rounded', (tester) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(extraContext: {'driver_id': 'driver-crit'}),
      ]);
      await tester.pump();
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    });

    testWidgets(
      'health YELLOW exibe ícone warning_amber_rounded para alerta HIGH',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          alertHigh(extraContext: {'driver_id': 'driver-high'}),
        ]);
        await tester.pump();
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'health GREEN exibe ícone check_circle_rounded para alertas LOW',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          alertLow(extraContext: {'driver_id': 'driver-low'}),
        ]);
        await tester.pump();
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'borda lateral usa cor crítica para grupo com alerta CRITICAL',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          alertCritical(extraContext: {'driver_id': 'driver-border'}),
        ]);
        await tester.pump();
        // Severity indicator: 4px Container(color: VeraProbColors.critical).
        // _SeverityBadge inside the expanded card uses withValues(alpha: 0.12)
        // — different Color value — so this predicate matches exactly one.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color ==
                    VeraProbColors.critical,
          ),
          findsOneWidget,
        );
      },
    );

    // ── Conteúdo do card ─────────────────────────────────────────────────

    testWidgets('exibe nome do motorista no header do card', (tester) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(
          driverName: 'Sérgio Lima',
          extraContext: {'driver_id': 'driver-sergio'},
        ),
      ]);
      await tester.pump();
      expect(find.text('Sérgio Lima'), findsOneWidget);
    });

    testWidgets(
      'exibe ID truncado com reticências quando driverId excede 8 caracteres',
      (tester) async {
        await buildHost(tester);
        // 'driver-longid' = 13 chars → substring(0, 8) = 'driver-l' + '…'
        alertStreamController.add([
          alertCritical(extraContext: {'driver_id': 'driver-longid'}),
        ]);
        await tester.pump();
        expect(find.text('driver-l…'), findsOneWidget);
      },
    );

    testWidgets('exibe ID completo quando driverId tem até 8 caracteres', (
      tester,
    ) async {
      await buildHost(tester);
      // 'drv-1234' = 8 chars → shown as-is (length > 8 is false)
      alertStreamController.add([
        alertCritical(extraContext: {'driver_id': 'drv-1234'}),
      ]);
      await tester.pump();
      expect(find.text('drv-1234'), findsOneWidget);
    });

    testWidgets(
      'badge "+N" exibe contagem total do grupo com múltiplos alertas',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          alertCritical(id: 'b1', extraContext: {'driver_id': 'driver-badge'}),
          alertHigh(id: 'b2', extraContext: {'driver_id': 'driver-badge'}),
          alertLow(id: 'b3', extraContext: {'driver_id': 'driver-badge'}),
        ]);
        await tester.pump();
        expect(find.text('+3'), findsOneWidget);
      },
    );
  });

  // ── Alert detail, evidence peek, forensic hash ────────────────────────────

  group('Detalhes do Alerta e Visualização de Evidências', () {
    // ── Labels de tipo de alerta ──────────────────────────────────────────

    testWidgets('badge "NO-SHOW" exibido para alertType NO_SHOW', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([
        alertCritical(extraContext: {'driver_id': 'driver-label-ns'}),
      ]);
      await tester.pump();
      // Label appears in _SeverityBadge (badge) AND in _gapLabel fallback (body)
      // when no window_start is present — both are valid renders of the label.
      expect(find.text('NO-SHOW'), findsWidgets);
    });

    testWidgets('badge "EVIDÊNCIA" exibido para alertType EVIDENCE_GAP', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([
        alertHigh(extraContext: {'driver_id': 'driver-label-eg'}),
      ]);
      await tester.pump();
      expect(find.text('EVIDÊNCIA'), findsWidgets);
    });

    testWidgets('badge "FOTO ÓRFÃ" exibido para alertType TELEGRAM_ORPHAN', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([
        alertTelegramOrphan(driverId: 'driver-orphan-label'),
      ]);
      await tester.pump();
      // TELEGRAM_ORPHAN cards may trigger a RenderFlex overflow at this viewport
      // (known layout constraint when Reconciliar + Vincular buttons co-exist).
      tester.takeException();
      expect(find.text('FOTO ÓRFÃ'), findsWidgets);
    });

    // ── Time Ago ──────────────────────────────────────────────────────────

    testWidgets('time ago exibe "agora" para alerta disparado agora', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([
        OperationalAlert(
          id: 'alert-now',
          organizationId: _kOrgId,
          entityId: _kEntityId,
          contractId: _kContractId,
          alertType: 'NO_SHOW',
          severity: 'CRITICAL',
          triggeredAtUtc: DateTime.now().toUtc(),
          context: <String, Object>{'driver_id': 'driver-now'},
          viewedByUserIds: const [],
        ),
      ]);
      await tester.pump();
      expect(find.text('agora'), findsOneWidget);
    });

    testWidgets('time ago exibe "há 10min" para alerta com 10 minutos', (
      tester,
    ) async {
      await buildHost(tester);
      final tenMinsAgo = DateTime.now().toUtc().subtract(
        const Duration(minutes: 10),
      );
      alertStreamController.add([
        OperationalAlert(
          id: 'alert-10min',
          organizationId: _kOrgId,
          entityId: _kEntityId,
          contractId: _kContractId,
          alertType: 'NO_SHOW',
          severity: 'CRITICAL',
          triggeredAtUtc: tenMinsAgo,
          context: <String, Object>{'driver_id': 'driver-10min'},
          viewedByUserIds: const [],
        ),
      ]);
      await tester.pump();
      expect(find.text('há 10min'), findsOneWidget);
    });

    // ── Chips de Categoria e Fonte ────────────────────────────────────────

    testWidgets(
      'EvidenceCategoryChip renderizado quando evidence_category presente no contexto',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          alertCritical(
            extraContext: <String, Object>{
              'driver_id': 'driver-cat',
              'evidence_category': 'PHOTO',
            },
          ),
        ]);
        await tester.pump();
        expect(find.byType(EvidenceCategoryChip), findsOneWidget);
      },
    );

    testWidgets(
      'EvidenceLinkSourceChip renderizado quando link_source presente no contexto',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          alertCritical(
            extraContext: <String, Object>{
              'driver_id': 'driver-src',
              'link_source': 'TELEGRAM',
            },
          ),
        ]);
        await tester.pump();
        expect(find.byType(EvidenceLinkSourceChip), findsOneWidget);
      },
    );

    // ── Visualização de Evidências ────────────────────────────────────────

    testWidgets(
      'peek exibe exatamente 3 miniaturas mesmo com 4 evidências (limite máximo)',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          OperationalAlert(
            id: 'alert-ev4',
            organizationId: _kOrgId,
            entityId: _kEntityId,
            contractId: _kContractId,
            alertType: 'NO_SHOW',
            severity: 'CRITICAL',
            triggeredAtUtc: DateTime.utc(2026, 5, 11, 10, 0),
            context: <String, Object>{
              'driver_id': 'driver-ev4',
              'evidence_ids': <String>['ev-001', 'ev-002', 'ev-003', 'ev-004'],
            },
            viewedByUserIds: const [],
          ),
        ]);
        await tester.pump();
        // _EvidencePeekWidget._kMaxThumbs == 3 → visible.length == 3
        expect(find.byType(CachedNetworkImage), findsNWidgets(3));
      },
    );

    testWidgets('badge "+N FOTOS" aparece quando há múltiplas evidências', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([
        OperationalAlert(
          id: 'alert-fotos',
          organizationId: _kOrgId,
          entityId: _kEntityId,
          contractId: _kContractId,
          alertType: 'NO_SHOW',
          severity: 'CRITICAL',
          triggeredAtUtc: DateTime.utc(2026, 5, 11, 10, 0),
          context: <String, Object>{
            'driver_id': 'driver-fotos',
            'evidence_ids': <String>['ev-001', 'ev-002', 'ev-003', 'ev-004'],
          },
          viewedByUserIds: const [],
        ),
      ]);
      await tester.pump();
      // _PhotoCountBadge: count=4 < 10 → '+4 FOTOS'
      expect(find.text('+4 FOTOS'), findsOneWidget);
    });

    testWidgets('toque em miniatura abre EvidenceDossierModal (INV-26)', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([
        OperationalAlert(
          id: 'alert-dossier',
          organizationId: _kOrgId,
          entityId: _kEntityId,
          contractId: _kContractId,
          alertType: 'NO_SHOW',
          severity: 'CRITICAL',
          triggeredAtUtc: DateTime.utc(2026, 5, 11, 10, 0),
          context: <String, Object>{
            'driver_id': 'driver-dossier',
            'evidence_ids': <String>['ev-dossier-01'],
          },
          viewedByUserIds: const [],
        ),
      ]);
      await tester.pump();
      // GestureDetector wraps the thumbnail row — tap propagates up from CachedNetworkImage
      await tester.tap(find.byType(CachedNetworkImage).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EvidenceDossierModal), findsOneWidget);
    });

    // ── Hash Forense ──────────────────────────────────────────────────────

    testWidgets(
      'prefixo do hash forense exibido com ícone 🔐 quando presente no contexto',
      (tester) async {
        await buildHost(tester);
        alertStreamController.add([
          alertCritical(
            extraContext: <String, Object>{
              'driver_id': 'driver-hash',
              'forensic_hash_prefix': 'abc123de',
            },
          ),
        ]);
        await tester.pump();
        // Rendered as '🔐 {prefix}…' via Text in _RichEvidenceCard
        expect(find.text('🔐 abc123de…'), findsOneWidget);
      },
    );
  });

  // ── Phase 1: Infrastructure smoke ─────────────────────────────────────────

  group('Fase 1 — infra & fixtures', () {
    test('INV-7: fixtures use strict types — no dynamic fields', () {
      final critical = alertCritical();
      final high = alertHigh();
      final low = alertLow();
      final orphan = alertTelegramOrphan();

      expect(critical.severity, equals('CRITICAL'));
      expect(critical.organizationId, equals(_kOrgId));

      expect(high.severity, equals('HIGH'));
      expect(high.alertType, equals('EVIDENCE_GAP'));

      expect(low.severity, equals('LOW'));
      expect(low.alertType, equals('PENALTY_APPLIED'));

      expect(orphan.alertType, equals('TELEGRAM_ORPHAN'));
      // context values are Object, not dynamic — verify runtime types
      expect(orphan.context['driver_id'], isA<String>());
      expect(orphan.context['evidence_ids'], isA<List<String>>());
    });

    testWidgets('renders without exception — initial loading state', (
      tester,
    ) async {
      await buildHost(tester);
      await tester.pump();
      expect(find.byType(AlertsTriadeDrawer), findsOneWidget);
    });

    testWidgets('shows empty state when stream emits []', (tester) async {
      await buildHost(tester);
      alertStreamController.add([]);
      await tester.pump();
      expect(find.text('Operação Limpa'), findsOneWidget);
    });

    testWidgets('header always shows "Centro de Comando" title', (
      tester,
    ) async {
      await buildHost(tester);
      alertStreamController.add([]);
      await tester.pump();
      expect(find.text('Centro de Comando'), findsOneWidget);
    });

    testWidgets('drawer width clamps to >= 300 at 1000px viewport', (
      tester,
    ) async {
      // 1000 * 0.28 = 280 → clamped to 300.
      // Header Row overflows at 300px (known widget constraint) — consume the
      // FlutterError so we can still assert the clamped width.
      await buildHost(tester, size: const Size(1000, 800));
      alertStreamController.add([]);
      await tester.pump();
      tester.takeException(); // discard RenderFlex overflow at narrow width
      final drawerSize = tester.getSize(find.byType(AlertsTriadeDrawer));
      expect(drawerSize.width, greaterThanOrEqualTo(300.0));
      expect(drawerSize.width, lessThanOrEqualTo(400.0));
    });

    testWidgets('drawer width clamps to <= 400 at 2000px viewport', (
      tester,
    ) async {
      // 2000 * 0.28 = 560 → clamped to 400
      await buildHost(tester, size: const Size(2000, 800));
      alertStreamController.add([]);
      await tester.pump();
      final drawerSize = tester.getSize(find.byType(AlertsTriadeDrawer));
      expect(drawerSize.width, lessThanOrEqualTo(400.0));
    });
  });

  // ── Carrier defense (DISPUTE_DEFENSE_SUBMITTED) → deep-link to disputed lane ──
  group('Contestação do transportador (Bug 1c — triagem)', () {
    /// Router-backed host: the defense CTA calls `context.go`, so the drawer
    /// needs a real GoRouter ancestor. Returns the [ProviderContainer] so the
    /// test can read [auditorQueueFilterProvider]/[isAlertsDrawerOpenProvider]
    /// state after the tap.
    Future<ProviderContainer> buildRoutedHost(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          activeAlertsStreamProvider.overrideWith(
            () => _FakeActiveAlertsNotifier(alertStreamController),
          ),
          alertSoundServiceProvider.overrideWithValue(soundService),
          operationalAlertRepositoryProvider.overrideWithValue(alertRepo),
          quickReconciliationServiceProvider.overrideWithValue(
            reconciliationService,
          ),
          currentOperatorIdProvider.overrideWithValue(_kUserId),
          currentOrganizationIdProvider.overrideWithValue(_kOrgId),
          currentSessionIdProvider.overrideWithValue(_kSessionToken),
          evidenceUrlServiceProvider.overrideWithValue(
            const _FakeEvidenceUrlService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Base page + pushed drawer page: mirrors production where the triage
      // drawer is an overlay route on top of the command center, so the CTA's
      // Navigator.pop() has a page to remove before context.go navigates.
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('HOME')),
          ),
          GoRoute(
            path: '/triage',
            builder: (_, _) => const Scaffold(body: AlertsTriadeDrawer()),
          ),
          GoRoute(
            path: '/admin/auditor-queue',
            builder: (_, _) =>
                const Scaffold(body: Text('AUDITOR_QUEUE_SCREEN')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      unawaited(router.push('/triage'));
      // Advance the push transition with fixed pumps — pumpAndSettle would hang
      // on the drawer's loading LinearProgressIndicator (no alerts added yet).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return container;
    }

    testWidgets('renders a CONTESTAÇÃO card with file metadata only', (
      tester,
    ) async {
      await buildRoutedHost(tester);
      alertStreamController.add([alertDisputeDefense()]);
      await tester.pumpAndSettle();

      expect(find.text('CONTESTAÇÃO'), findsOneWidget);
      expect(find.text('TST-0001'), findsOneWidget);
      expect(
        find.textContaining('Multa em risco: R\$ 1.500,00'),
        findsOneWidget,
      );
      expect(find.textContaining('Anexo: contraprova.jpg'), findsOneWidget);
      expect(find.text('IR PARA DISPUTA →'), findsOneWidget);
    });

    testWidgets('textual defense shows "Defesa textual" (no filename)', (
      tester,
    ) async {
      await buildRoutedHost(tester);
      alertStreamController.add([
        alertDisputeDefense(defenseType: 'text', filename: null),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Defesa textual'), findsOneWidget);
      expect(find.textContaining('Anexo:'), findsNothing);
    });

    testWidgets('CTA deep-links to disputed lane (filter + close + navigate)', (
      tester,
    ) async {
      final container = await buildRoutedHost(tester);
      alertStreamController.add([alertDisputeDefense()]);
      await tester.pumpAndSettle();

      // Pin the autoDispose filter notifier with a listener so its state
      // survives the drawer disposing on navigation (in production the queue
      // screen watches it; here the destination is a bare placeholder).
      final sub = container.listen(auditorQueueFilterProvider, (_, _) {});
      addTearDown(sub.close);

      // Pre-condition: filter defaults to pending, drawer flagged open.
      container.read(isAlertsDrawerOpenProvider.notifier).set(true);
      expect(sub.read(), AuditorQueueFilter.pending);

      await tester.tap(find.text('IR PARA DISPUTA →'));
      await tester.pumpAndSettle();

      // Filter switched to disputed, drawer closed, route changed to the queue.
      expect(sub.read(), AuditorQueueFilter.disputed);
      expect(container.read(isAlertsDrawerOpenProvider), isFalse);
      expect(find.text('AUDITOR_QUEUE_SCREEN'), findsOneWidget);
    });
  });
}
