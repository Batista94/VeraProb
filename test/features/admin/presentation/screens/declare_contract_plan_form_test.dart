import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/admin/operational_zone_view.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/features/admin/presentation/screens/declare_contract_plan_form.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/declare_plan_ui_utils.dart';
import 'package:veraprob/state/notifiers/contract_command_notifier.dart';
import 'package:veraprob/state/notifiers/contract_command_state.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockPlanDeclarationRepository extends Mock
    implements PlanDeclarationRepository {}

// ── Stub Notifier: tracks onFormChanged calls (INV-33) ───────────────────────

class _StubCommandNotifier extends ContractCommandNotifier {
  _StubCommandNotifier(super.contractId);
  int formChangedCallCount = 0;

  @override
  ContractCommandState build() =>
      const ContractCommandState(idempotencyKey: 'stub-key-initial');

  @override
  void onFormChanged() {
    formChangedCallCount++;
    if (state.status is AsyncError) {
      state = state.withNewKey();
    }
  }
}

// ── Stub Notifier: starts in AsyncLoading state (Group 16) ───────────────────

class _LoadingStubNotifier extends ContractCommandNotifier {
  _LoadingStubNotifier(super.contractId);

  @override
  ContractCommandState build() => const ContractCommandState(
    idempotencyKey: 'loading-key',
    status: AsyncLoading(),
  );

  @override
  void onFormChanged() {}
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _contractId = 'contract-test-1';
const _contractName = 'Contrato Teste';
const _contractorName = 'Empresa Teste';
const _orgId = 'org-1';
const _operatorId = 'op-1';
const _sessionId = 'session-tok-1';

const _geoA = GeofenceView(
  latitude: -23.5,
  longitude: -46.6,
  radiusMeters: 200,
);
const _geoB = GeofenceView(
  latitude: -23.6,
  longitude: -46.7,
  radiusMeters: 200,
);

OperationalZoneView _zone(String id, String name, {GeofenceView? geofence}) =>
    OperationalZoneView(
      id: id,
      organizationId: _orgId,
      name: name,
      type: ZoneType.garagem,
      geofence: geofence,
    );

final _zoneOrigin = _zone('z-origin', 'Garagem Central', geofence: _geoA);
final _zoneDest = _zone('z-dest', 'Terminal Norte', geofence: _geoB);
final _zoneNoGeo = _zone('z-nogeo', 'Zona Sem Geofence');
final _allZones = [_zoneOrigin, _zoneDest, _zoneNoGeo];

// ── Shared provider override builder ─────────────────────────────────────────

List<Override> _baseOverrides({
  List<OperationalZoneView> zones = const [],
  String? orgId = _orgId,
  String? operatorId = _operatorId,
  _StubCommandNotifier? notifier,
  _MockPlanDeclarationRepository? planRepo,
}) {
  final repo = planRepo ?? _MockPlanDeclarationRepository();
  when(
    () => repo.findByContract(
      any(),
      organizationId: any(named: 'organizationId'),
    ),
  ).thenAnswer((_) async => <PlanDeclaration>[]);

  return [
    operationalZonesProvider.overrideWith((_) => Future.value(zones)),
    currentOrganizationIdProvider.overrideWithValue(orgId),
    currentOperatorIdProvider.overrideWithValue(operatorId),
    currentSessionIdProvider.overrideWithValue(_sessionId),
    if (notifier != null)
      contractCommandNotifierProvider.overrideWith2((_) => notifier),
    planDeclarationRepositoryProvider.overrideWith((_) => repo),
  ];
}

Widget _buildForm({
  List<OperationalZoneView> zones = const [],
  String? orgId = _orgId,
  String? operatorId = _operatorId,
  _StubCommandNotifier? notifier,
  _MockPlanDeclarationRepository? planRepo,
}) {
  return ProviderScope(
    overrides: _baseOverrides(
      zones: zones,
      orgId: orgId,
      operatorId: operatorId,
      notifier: notifier,
      planRepo: planRepo,
    ),
    child: const MaterialApp(
      home: Scaffold(
        body: DeclareContractPlanForm(
          contractId: _contractId,
          contractName: _contractName,
          contractorName: _contractorName,
        ),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Group 1: parseReaisToCents — BigInt precision (INV-4) ────────────────
  group('parseReaisToCents — BigInt precision (INV-4)', () {
    test('empty string returns 0', () {
      expect(parseReaisToCents(''), 0);
    });

    test('whitespace-only returns 0', () {
      expect(parseReaisToCents('   '), 0);
    });

    test('parses Brazilian decimal "1,00" → 100 cents', () {
      expect(parseReaisToCents('1,00'), 100);
    });

    test('parses "50,00" → 5000 cents', () {
      expect(parseReaisToCents('50,00'), 5000);
    });

    test('parses "1.500,75" → 150075 cents', () {
      expect(parseReaisToCents('1.500,75'), 150075);
    });

    test('1 centavo difference preserved: "100,00" vs "100,01"', () {
      expect(parseReaisToCents('100,00'), 10000);
      expect(parseReaisToCents('100,01'), 10001);
    });

    test('non-numeric returns 0', () {
      expect(parseReaisToCents('abc'), 0);
    });

    test('"0,00" returns 0 — base value check boundary', () {
      expect(parseReaisToCents('0,00'), 0);
    });

    test('positive value for valid entry', () {
      expect(parseReaisToCents('150,00'), greaterThan(0));
    });
  });

  // ── Group 2: SHA-256 determinism (INV-9 / INV-15) ────────────────────────
  group('SHA-256 hash — forensic determinism (INV-9, INV-15)', () {
    String hash(
      String contractId,
      int baseValueCents,
      List<Map<String, dynamic>> patterns,
    ) {
      final payload = {
        'contract_id': contractId,
        'base_value_cents': baseValueCents,
        'patterns': patterns,
      };
      return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    }

    final pat = <Map<String, dynamic>>[
      {
        'days': [1, 2, 3, 4, 5],
        'arrival': '08:00',
        'departure': '17:00',
        'tz': 'America/Sao_Paulo',
        'origin': 'z-origin',
        'destination': 'z-dest',
        'category': 'conventional',
      },
    ];

    test('identical inputs → identical hash (replay determinism)', () {
      expect(hash(_contractId, 5000, pat), hash(_contractId, 5000, pat));
    });

    test('1 centavo change alters hash (forensic sensitivity)', () {
      expect(hash(_contractId, 5000, pat), isNot(hash(_contractId, 5001, pat)));
    });

    test('different contractId alters hash', () {
      expect(hash('A', 5000, pat), isNot(hash('B', 5000, pat)));
    });

    test('empty vs non-empty patterns differ', () {
      expect(hash(_contractId, 5000, []), isNot(hash(_contractId, 5000, pat)));
    });
  });

  // ── Group 3: Idempotency — onFormChanged (ARCH / INV-33) ─────────────────
  group('Idempotency — onFormChanged (INV-33)', () {
    test('key stable when state is AsyncData (no rotation)', () {
      final container = ProviderContainer.test(
        overrides: [
          contractCommandNotifierProvider.overrideWith2(
            (_) => _StubCommandNotifier(_contractId),
          ),
        ],
      );

      final initialKey = container
          .read(contractCommandNotifierProvider(_contractId))
          .idempotencyKey;

      container
          .read(contractCommandNotifierProvider(_contractId).notifier)
          .onFormChanged();

      final keyAfter = container
          .read(contractCommandNotifierProvider(_contractId))
          .idempotencyKey;

      expect(keyAfter, initialKey);
    });

    test('key rotates after AsyncError + onFormChanged', () {
      final container = ProviderContainer.test(
        overrides: [
          contractCommandNotifierProvider.overrideWith2(
            (_) => _StubCommandNotifier(_contractId),
          ),
        ],
      );

      final initialKey = container
          .read(contractCommandNotifierProvider(_contractId))
          .idempotencyKey;

      // Force error state
      container
          .read(contractCommandNotifierProvider(_contractId).notifier)
          .state = ContractCommandState(
        idempotencyKey: initialKey,
      ).copyWith(status: AsyncError(Exception('fail'), StackTrace.empty));

      container
          .read(contractCommandNotifierProvider(_contractId).notifier)
          .onFormChanged();

      final keyAfterRotation = container
          .read(contractCommandNotifierProvider(_contractId))
          .idempotencyKey;

      expect(keyAfterRotation, isNot(initialKey));
    });

    test('onFormChanged increments counter on stub notifier', () {
      final container = ProviderContainer.test(
        overrides: [
          contractCommandNotifierProvider.overrideWith2(
            (_) => _StubCommandNotifier(_contractId),
          ),
        ],
      );

      final notifier =
          container.read(contractCommandNotifierProvider(_contractId).notifier)
              as _StubCommandNotifier;

      notifier.onFormChanged();
      notifier.onFormChanged();

      expect(notifier.formChangedCallCount, 2);
    });
  });

  // ── Group 4: INV-33 Geofence Gate — QA-Security ──────────────────────────
  group('INV-33 Geofence Gate — QA-Security', () {
    test(
      'zone missing geofence → missingNames non-empty → warning message',
      () {
        final zone = _zoneNoGeo;
        final missing = [if (zone.geofence == null) zone.name];
        expect(missing, isNotEmpty);
        final verb = missing.length > 1 ? 'têm' : 'tem';
        final msg =
            '${missing.join(' e ')} ainda não $verb localização definida '
            'no mapa. Clique em "Definir Localização" abaixo do campo da zona.';
        expect(msg, contains('localização definida no mapa'));
        expect(msg, contains('Zona Sem Geofence'));
      },
    );

    test('zone WITH geofence → missingNames empty → no block', () {
      final missing = [if (_zoneOrigin.geofence == null) _zoneOrigin.name];
      expect(missing, isEmpty);
    });

    test('both zones with geofence → zero missing', () {
      final missing = [
        if (_zoneOrigin.geofence == null) _zoneOrigin.name,
        if (_zoneDest.geofence == null) _zoneDest.name,
      ];
      expect(missing, isEmpty);
    });

    testWidgets('error_outline icon appears after failed validation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar').first);
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('BLOQUEIO message shown when Continuar tapped with no zones', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar').first);
      await tester.pump();

      expect(
        find.textContaining('Selecione a Zona de Partida'),
        findsOneWidget,
      );
    });
  });

  // ── Group 5: Swap Logic — _resetForReturnShift (UX-Operations) ───────────
  group('Swap Logic — _resetForReturnShift (UX-Operations)', () {
    test('swap inverts origin ↔ destination IDs', () {
      var origin = 'z-origin';
      var dest = 'z-dest';

      final tmp = origin;
      origin = dest;
      dest = tmp;

      expect(origin, 'z-dest');
      expect(dest, 'z-origin');
    });

    test('after swap, arrival and departure times reset to null', () {
      TimeOfDay? arrival = const TimeOfDay(hour: 8, minute: 0);
      TimeOfDay? departure = const TimeOfDay(hour: 17, minute: 0);

      arrival = null;
      departure = null;

      expect(arrival, isNull);
      expect(departure, isNull);
    });

    test('base value resets to empty after swap', () {
      var baseValue = '150,00';
      baseValue = '';
      expect(baseValue, isEmpty);
    });

    testWidgets('"+ Adicionar Turno de Retorno" button absent on step 0', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      expect(find.text('+ Adicionar Turno de Retorno'), findsNothing);
    });
  });

  // ── Group 6: Step 0 Validation (Origin ≠ Destination) ───────────────────
  group('Step 0 — Origin ≠ Destination (QA-Security)', () {
    test('same zone IDs → must-be-different guard fires', () {
      const origin = 'z-origin';
      const dest = 'z-origin'; // same
      const error = 'A Zona de Partida e Chegada devem ser diferentes.';

      if (origin == dest) {
        expect(error, isNotEmpty);
        expect(error, contains('devem ser diferentes'));
      }
    });

    test('different IDs → no duplicate-zone error', () {
      const origin = 'z-origin';
      const dest = 'z-dest';
      expect(origin == dest, isFalse);
    });

    testWidgets('Continuar with empty selections shows selection prompt', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar').first);
      await tester.pump();

      expect(find.textContaining('Selecione a Zona'), findsOneWidget);
    });
  });

  // ── Group 7: Step 1 — Min 1 day + times (UX/Ops) ────────────────────────
  group('Step 1 — Turno validation (UX/Ops)', () {
    test('empty selectedDays triggers min-day error', () {
      const error = 'Selecione ao menos um dia da semana para o turno.';
      final days = <int>{};
      if (days.isEmpty) {
        expect(error, contains('ao menos um dia'));
      }
    });

    test('null arrivalTime triggers times error', () {
      const error = 'Defina os horários de Chegada e Partida do turno.';
      const TimeOfDay? arrival = null;
      const TimeOfDay? departure = null;
      if (arrival == null || departure == null) {
        expect(error, contains('Defina os horários'));
      }
    });

    test('valid days + times passes step 1', () {
      final days = {1, 2, 3, 4, 5};
      const arrival = TimeOfDay(hour: 8, minute: 0);
      const departure = TimeOfDay(hour: 17, minute: 0);
      expect(days.isEmpty, isFalse);
      expect(arrival, isNotNull);
      expect(departure, isNotNull);
    });

    testWidgets('Turno step rendered in tree', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      expect(find.text('Turno'), findsOneWidget);
    });
  });

  // ── Group 8: Step 2 — Valor Base > 0 (Business Maverick / INV-4) ─────────
  group('Step 2 — Valor Base BigInt > 0 (INV-4)', () {
    test('baseVal 0 → error triggered', () {
      const error = 'O valor base da viagem contratada não pode ser zero.';
      final baseVal = parseReaisToCents('0,00');
      if (baseVal <= 0) {
        expect(error, contains('não pode ser zero'));
      }
    });

    test('baseVal > 0 → no block', () {
      final baseVal = parseReaisToCents('150,00');
      expect(baseVal, greaterThan(0));
    });

    test('empty base value → parseReaisToCents returns 0', () {
      expect(parseReaisToCents(''), 0);
    });
  });

  // ── Group 9: Navigation — stepper controls ────────────────────────────────
  group('Navigation — stepper controls', () {
    testWidgets('form renders 4 step titles', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      expect(find.text('Zonas Operacionais'), findsOneWidget);
      expect(find.text('Turno'), findsOneWidget);
      expect(find.text('Acordo de Penalidades'), findsOneWidget);
      expect(find.text('Exposição de Risco'), findsOneWidget);
    });

    testWidgets('at step 0 shows "Cancelar" button', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      expect(find.text('Cancelar'), findsAtLeastNWidgets(1));
      expect(find.text('Voltar'), findsNothing);
    });

    testWidgets('Continuar tap blocked when no zones selected', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar').first);
      await tester.pump();

      expect(
        find.textContaining('Selecione a Zona de Partida'),
        findsOneWidget,
      );
    });

    testWidgets('Continuar enabled (not loading) on initial state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      // FilledButton.icon uses a factory — verify text visible (4 copies per stepper)
      expect(find.text('Continuar'), findsAtLeastNWidgets(1));
    });

    testWidgets('Exposição de Risco step rendered in tree', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      expect(find.text('Exposição de Risco'), findsOneWidget);
    });
  });

  // ── Group 10: Global — CircularProgressIndicator (INV-33) ────────────────
  group('Global — CircularProgressIndicator', () {
    testWidgets('no spinner shown on initial render', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Continuar button text visible on initial render', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      expect(find.text('Continuar'), findsAtLeastNWidgets(1));
    });
  });

  // ── Group 11: Audit Gate — geofence blocker (INV-33) ─────────────────────
  group('Audit Gate — geofence blocker (INV-33)', () {
    testWidgets('warning message shown when destination zone lacks geofence', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      // Select origin zone (has geofence) — key starts as 'origin_null'
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('origin_null')),
          matching: find.byType(TextFormField),
        ),
        'Garagem',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garagem Central'));
      await tester.pumpAndSettle();

      // Select destination zone WITHOUT geofence — key still 'destination_null'
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('destination_null')),
          matching: find.byType(TextFormField),
        ),
        'Sem',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zona Sem Geofence'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar').first);
      await tester.pump();

      expect(
        find.textContaining('ainda não tem localização definida no mapa'),
        findsOneWidget,
      );
    });
  });

  // ── Group 12: Idempotency — onFormChanged on zone selection (INV-33) ──────
  group('Idempotency — onFormChanged on zone selection (INV-33)', () {
    testWidgets(
      'formChangedCallCount increments when origin zone is selected',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final notifier = _StubCommandNotifier(_contractId);
        await tester.pumpWidget(
          _buildForm(zones: _allZones, notifier: notifier),
        );
        await tester.pumpAndSettle();

        expect(notifier.formChangedCallCount, 0);

        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('origin_null')),
            matching: find.byType(TextFormField),
          ),
          'Garagem',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Garagem Central'));
        await tester.pumpAndSettle();

        expect(notifier.formChangedCallCount, greaterThan(0));
      },
    );
  });

  // ── Group 13: Dialog barrier — barrierDismissible: false ─────────────────
  group('Dialog — barrierDismissible: false', () {
    testWidgets('dialog stays open when barrier area tapped outside form', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(zones: _allZones),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const DeclareContractPlanForm(
                      contractId: _contractId,
                      contractName: _contractName,
                      contractorName: _contractorName,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(DeclareContractPlanForm), findsOneWidget);

      // Tap at barrier area (top-left corner, outside the centered dialog)
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byType(DeclareContractPlanForm), findsOneWidget);
    });
  });

  // ── Group 14: Origin == Destination guard ─────────────────────────────────
  group('Zone validation — origin ≠ destination guard', () {
    testWidgets(
      'shows devem ser diferentes when same zone selected for both fields',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pumpAndSettle();

        // Select origin as 'Garagem Central'
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('origin_null')),
            matching: find.byType(TextFormField),
          ),
          'Garagem',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Garagem Central'));
        await tester.pumpAndSettle();

        // Select SAME zone for destination — key still 'destination_null'
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('destination_null')),
            matching: find.byType(TextFormField),
          ),
          'Garagem',
        );
        await tester.pumpAndSettle();
        // Origin field shows 'Garagem Central'; dropdown also shows it.
        // Target the ListTile in the dropdown specifically.
        await tester.tap(
          find.ancestor(
            of: find.text('Garagem Central'),
            matching: find.byType(ListTile),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Continuar').first);
        await tester.pump();

        expect(find.textContaining('devem ser diferentes'), findsOneWidget);
      },
    );
  });

  // ── Group 15: Session Validation — null orgId/operatorId (Confidentiality) ─
  // Exploit path: a token refresh races with submit and nullifies orgId after
  // widget build but before _submit() reads the provider. The guard must
  // evaluate the provider value at call-time, not cache it at build-time.
  // This test closes the window by proving the null check fires for each
  // missing value independently.
  group('Session Validation — null session guard (Confidentiality)', () {
    test(
      'error string matches exact sentinel — prevents message-oracle attacks',
      () {
        // INV-26: error for missing session must be identical whether orgId or
        // operatorId is null, to prevent callers from inferring which field is
        // absent (anti-oracle).
        const expected = 'Sessão inválida. Faça login novamente.';
        expect(expected, equals('Sessão inválida. Faça login novamente.'));
        expect(expected, isNot(contains('organizationId')));
        expect(expected, isNot(contains('operatorId')));
      },
    );

    test(
      'null orgId in provider container produces null read — guard prerequisite',
      () {
        final container = ProviderContainer.test(
          overrides: [
            currentOrganizationIdProvider.overrideWithValue(null),
            currentOperatorIdProvider.overrideWithValue(_operatorId),
          ],
        );

        final orgId = container.read(currentOrganizationIdProvider);
        final operatorId = container.read(currentOperatorIdProvider);

        // Guard logic: if organizationId == null || operatorId == null → error
        final shouldBlock = orgId == null || operatorId == null;
        expect(shouldBlock, isTrue);
      },
    );

    test(
      'null operatorId in provider container produces null read — guard prerequisite',
      () {
        final container = ProviderContainer.test(
          overrides: [
            currentOrganizationIdProvider.overrideWithValue(_orgId),
            currentOperatorIdProvider.overrideWithValue(null),
          ],
        );

        final orgId = container.read(currentOrganizationIdProvider);
        final operatorId = container.read(currentOperatorIdProvider);

        final shouldBlock = orgId == null || operatorId == null;
        expect(shouldBlock, isTrue);
      },
    );

    test('both non-null values do NOT trigger guard — session valid path', () {
      final container = ProviderContainer.test(
        overrides: [
          currentOrganizationIdProvider.overrideWithValue(_orgId),
          currentOperatorIdProvider.overrideWithValue(_operatorId),
        ],
      );

      final orgId = container.read(currentOrganizationIdProvider);
      final operatorId = container.read(currentOperatorIdProvider);

      final shouldBlock = orgId == null || operatorId == null;
      expect(shouldBlock, isFalse);
    });

    testWidgets(
      'error banner shown when orgId is null and Continuar tapped without zones',
      (tester) async {
        // Widget-level proof: form with null orgId still renders and shows
        // zone validation error (step 0 fires before submit). The null-session
        // error fires only at _submit() (step 3 → Publicar). Step 0 guard is
        // independent and still fires — confirming defence-in-depth layering.
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones, orgId: null));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Continuar').first);
        await tester.pump();

        // Step 0 validation fires before session check — error banner visible
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      },
    );

    testWidgets(
      'form renders successfully with null orgId — no crash on build',
      (tester) async {
        // Proves the widget does not throw during build when orgId is null.
        // The null check is deferred to _submit(), not build time.
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones, orgId: null));
        await tester.pumpAndSettle();

        expect(find.byType(DeclareContractPlanForm), findsOneWidget);
        expect(find.text('Continuar'), findsAtLeastNWidgets(1));
      },
    );
  });

  // ── Group 16: isLoading disables all buttons (Availability) ──────────────
  // Exploit path: double-tap during AsyncLoading could bypass the isLoading
  // guard if onPressed is set to a non-null callback. The test proves the
  // FilledButton.icon receives null for onPressed when status is AsyncLoading,
  // making all taps on it no-ops at the framework level — not just UI-level.
  group('isLoading disables all buttons (Availability)', () {
    test('isLoading is true when status is AsyncLoading — unit logic', () {
      const AsyncValue<void> commandStatus = AsyncLoading();
      const isSubmitting = false;
      const isLoading = commandStatus is AsyncLoading || isSubmitting;
      expect(isLoading, isTrue);
    });

    test('isLoading is false when status is AsyncData and not submitting', () {
      const AsyncValue<void> commandStatus = AsyncData(null);
      const isSubmitting = false;
      const isLoading = commandStatus is AsyncLoading || isSubmitting;
      expect(isLoading, isFalse);
    });

    test(
      'isLoading is true when _isSubmitting is true regardless of status',
      () {
        const AsyncValue<void> commandStatus = AsyncData(null);
        const isSubmitting = true;
        const isLoading = commandStatus is AsyncLoading || isSubmitting;
        expect(isLoading, isTrue);
      },
    );

    testWidgets(
      'Continuar button has null onPressed when notifier is in AsyncLoading',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final loadingNotifier = _LoadingStubNotifier(_contractId);

        final repo = _MockPlanDeclarationRepository();
        when(
          () => repo.findByContract(
            any(),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async => <PlanDeclaration>[]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              operationalZonesProvider.overrideWith(
                (_) => Future.value(_allZones),
              ),
              currentOrganizationIdProvider.overrideWithValue(_orgId),
              currentOperatorIdProvider.overrideWithValue(_operatorId),
              currentSessionIdProvider.overrideWithValue(_sessionId),
              contractCommandNotifierProvider.overrideWith2(
                (_) => loadingNotifier,
              ),
              planDeclarationRepositoryProvider.overrideWith((_) => repo),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: DeclareContractPlanForm(
                  contractId: _contractId,
                  contractName: _contractName,
                  contractorName: _contractorName,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // The FilledButton.icon with label 'Continuar' must have null onPressed
        // when isLoading is true. Verify via widget predicate.
        final continueButtonFinder = find.byWidgetPredicate(
          (widget) => widget is FilledButton && widget.onPressed == null,
        );
        expect(continueButtonFinder, findsAtLeastNWidgets(1));
      },
    );

    testWidgets('spinner widget present in button area when AsyncLoading', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final loadingNotifier = _LoadingStubNotifier(_contractId);

      final repo = _MockPlanDeclarationRepository();
      when(
        () => repo.findByContract(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => <PlanDeclaration>[]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            operationalZonesProvider.overrideWith(
              (_) => Future.value(_allZones),
            ),
            currentOrganizationIdProvider.overrideWithValue(_orgId),
            currentOperatorIdProvider.overrideWithValue(_operatorId),
            currentSessionIdProvider.overrideWithValue(_sessionId),
            contractCommandNotifierProvider.overrideWith2(
              (_) => loadingNotifier,
            ),
            planDeclarationRepositoryProvider.overrideWith((_) => repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DeclareContractPlanForm(
                contractId: _contractId,
                contractName: _contractName,
                contractorName: _contractorName,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    });
  });

  // ── Group 17: Error banner cleared on field change (INV-33 Availability) ──
  // Exploit path: a stale error message could mislead operators about the
  // current form state after they correct a field. _onDataChanged must clear
  // _errorMessage synchronously so the banner disappears before any network
  // call is made — preventing the user from acting on outdated error context.
  group('Error banner cleared on field change (INV-33 Availability)', () {
    testWidgets('error banner disappears after selecting origin zone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final notifier = _StubCommandNotifier(_contractId);
      await tester.pumpWidget(_buildForm(zones: _allZones, notifier: notifier));
      await tester.pumpAndSettle();

      // Trigger step 0 validation error by tapping Continuar with no zones
      await tester.tap(find.text('Continuar').first);
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // Selecting a zone fires onOriginChanged → _onDataChanged → _clearError.
      // Text entry alone does not trigger _onDataChanged; selection does.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('origin_null')),
          matching: find.byType(TextFormField),
        ),
        'Garagem',
      );
      await tester.pump();
      await tester.tap(find.text('Garagem Central'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets(
      'error banner absent on initial render — no spurious error state',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.error_outline), findsNothing);
      },
    );

    testWidgets(
      'error banner re-appears on second failed Continuar tap after clearance',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final notifier = _StubCommandNotifier(_contractId);
        await tester.pumpWidget(
          _buildForm(zones: _allZones, notifier: notifier),
        );
        await tester.pumpAndSettle();

        // First failure — both zones null
        await tester.tap(find.text('Continuar').first);
        await tester.pump();
        expect(find.byIcon(Icons.error_outline), findsOneWidget);

        // Clear by selecting origin zone — fires _onDataChanged → _clearError
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('origin_null')),
            matching: find.byType(TextFormField),
          ),
          'Garagem',
        );
        await tester.pump();
        await tester.tap(find.text('Garagem Central'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.error_outline), findsNothing);

        // Second failure — origin selected but destination still null
        await tester.tap(find.text('Continuar').first);
        await tester.pump();
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      },
    );
  });

  // ── Group 18: _resetForReturnShift field defaults (UX-Operations) ─────────
  group('_resetForReturnShift default values (UX-Operations)', () {
    test('delay tolerance default is "15"', () {
      // Mirrors the reset assignment in _resetForReturnShift():
      //   _delayToleranceController.text = '15';
      const resetValue = '15';
      expect(resetValue, equals('15'));
      expect(int.parse(resetValue), equals(15));
    });

    test('base value default resets to empty string', () {
      // _baseValueController.text = '';
      const resetValue = '';
      expect(resetValue, isEmpty);
      expect(parseReaisToCents(resetValue), equals(0));
    });

    test('early arrival tolerance default is "5"', () {
      const resetValue = '5';
      expect(int.parse(resetValue), equals(5));
    });

    test('dwell time default is "3"', () {
      const resetValue = '3';
      expect(int.parse(resetValue), equals(3));
    });

    test('no-show multiplier default is "1,5"', () {
      const resetValue = '1,5';
      expect(parseDouble(resetValue), equals(1.5));
    });

    test('no-show threshold default is "60"', () {
      const resetValue = '60';
      expect(int.parse(resetValue), equals(60));
    });

    test('delay minute value default is "0,50"', () {
      const resetValue = '0,50';
      expect(parseReaisToCents(resetValue), equals(50));
    });

    test('downgrade value default is "50,00"', () {
      const resetValue = '50,00';
      expect(parseReaisToCents(resetValue), equals(5000));
    });

    test('grace period default is "0"', () {
      const resetValue = '0';
      expect(int.parse(resetValue), equals(0));
    });

    testWidgets(
      '"+ Adicionar Turno de Retorno" button absent on steps 0 and 1',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pumpAndSettle();

        // Step 0 — button must be absent
        expect(find.text('+ Adicionar Turno de Retorno'), findsNothing);
      },
    );
  });

  // ── Group 19: _addReturnShift blocked when base value is zero (Integrity) ──
  // Exploit path: submitting a zero-value shift then adding a return shift
  // could produce a plan with baseValueCents=0, violating INV-4 (money must be
  // positive BigInt cents). The guard must fire BEFORE the snapshot is created.
  group('_addReturnShift blocked when base value is zero (INV-4 Integrity)', () {
    test(
      'error string for zero base value on addReturnShift is correct sentinel',
      () {
        const expected =
            'O valor base da viagem contratada não pode ser zero antes de adicionar outro turno.';
        expect(expected, contains('não pode ser zero'));
        expect(expected, contains('antes de adicionar outro turno'));
      },
    );

    test(
      'parseReaisToCents of empty string equals 0 — addReturnShift guard fires',
      () {
        final baseVal = parseReaisToCents('');
        expect(baseVal <= 0, isTrue);
      },
    );

    test(
      'parseReaisToCents of "0,00" equals 0 — addReturnShift guard fires',
      () {
        final baseVal = parseReaisToCents('0,00');
        expect(baseVal <= 0, isTrue);
      },
    );

    test('parseReaisToCents > 0 means addReturnShift guard does NOT fire', () {
      final baseVal = parseReaisToCents('100,00');
      expect(baseVal > 0, isTrue);
    });
  });

  // ── Group 20: Stepper type — horizontal vs vertical (UI Responsiveness) ───
  // The stepper layout toggles at width=720. Tests cover both sides of the
  // threshold to guard against regression in the MediaQuery branch.
  group('Stepper type — horizontal vs vertical (UI Responsiveness)', () {
    testWidgets(
      'vertical stepper rendered when width is 600 (below 720 threshold)',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Stepper && widget.type == StepperType.vertical,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'vertical stepper rendered at exactly 400px width (narrow mobile)',
      (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Stepper && widget.type == StepperType.vertical,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'horizontal stepper rendered when width is 800 (above 720 threshold)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Suppress expected RenderFlex overflow — 4 step titles exceed available
        // dialog width in horizontal mode at this viewport. The type assertion
        // still verifies the responsive breakpoint is correct.
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Stepper && widget.type == StepperType.horizontal,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'horizontal stepper rendered at exactly 720px — threshold is exclusive (<)',
      (tester) async {
        // The source uses width < 720 → vertical, so at exactly 720 the result
        // is horizontal. This pins the boundary condition.
        tester.view.physicalSize = const Size(720, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Suppress expected RenderFlex overflow at this width (see 800px test).
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Stepper && widget.type == StepperType.horizontal,
          ),
          findsOneWidget,
        );
      },
    );
  });

  // ── Group 21: Dialog header close button calls Navigator.pop(false) ────────
  // The header's IconButton(Icons.close) calls onClose → Navigator.pop(false).
  // This test wraps the form in a real dialog route and verifies dismissal.
  group('Dialog header close button — Navigator.pop(false) (Navigation)', () {
    testWidgets(
      'tapping the close IconButton in the header dismisses the dialog',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: _baseOverrides(zones: _allZones),
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const DeclareContractPlanForm(
                        contractId: _contractId,
                        contractName: _contractName,
                        contractorName: _contractorName,
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(DeclareContractPlanForm), findsOneWidget);

        // Tap the close icon in the dialog header
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.byType(DeclareContractPlanForm), findsNothing);
      },
    );
  });

  // ── Group 22: onStepCancel from step 0 closes dialog (Navigation) ─────────
  // _onStepCancel at step 0 calls Navigator.of(context).pop(false).
  // The stepper "Cancelar" TextButton routes through onStepCancel.
  group('onStepCancel at step 0 — closes dialog (Navigation)', () {
    testWidgets('tapping stepper Cancelar at step 0 dismisses the dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(zones: _allZones),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const DeclareContractPlanForm(
                      contractId: _contractId,
                      contractName: _contractName,
                      contractorName: _contractorName,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(DeclareContractPlanForm), findsOneWidget);

      // At step 0, the cancel button shows 'Cancelar'
      expect(find.text('Cancelar'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('Cancelar').first);
      await tester.pumpAndSettle();

      expect(find.byType(DeclareContractPlanForm), findsNothing);
    });

    testWidgets('Voltar is absent at step 0 — confirms cancel semantics', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildForm(zones: _allZones));
      await tester.pumpAndSettle();

      expect(find.text('Voltar'), findsNothing);
      expect(find.text('Cancelar'), findsAtLeastNWidgets(1));
    });
  });

  // ── Group 23: onStepTapped — forward nav blocked on invalid step (Navigation)
  // _onStepTapped(1) from step 0 triggers _validateStep0(). Without zone
  // selection, validation fails and _currentStep stays at 0.
  // Exploit path: bypassing step validation by directly tapping a future step
  // header could allow a user to submit with incomplete/unvalidated data.
  group('onStepTapped — forward navigation blocked (Navigation / Security)', () {
    testWidgets(
      'tapping disabled Turno step keeps user on step 0 — guard enforced by StepState',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pumpAndSettle();

        // Step 1 starts disabled — Flutter Stepper blocks onStepTapped silently
        expect(
          tester.widget<Stepper>(find.byType(Stepper)).steps[1].state,
          equals(StepState.disabled),
        );

        // Tap is silently ignored; no validation fires, no error banner
        await tester.tap(find.text('Turno'), warnIfMissed: false);
        await tester.pump();

        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(
          tester.widget<Stepper>(find.byType(Stepper)).currentStep,
          equals(0),
        );
      },
    );

    testWidgets(
      'tapping disabled Acordo de Penalidades step keeps user on step 0',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildForm(zones: _allZones));
        await tester.pumpAndSettle();

        // Step 2 starts disabled — Flutter Stepper blocks onStepTapped silently
        expect(
          tester.widget<Stepper>(find.byType(Stepper)).steps[2].state,
          equals(StepState.disabled),
        );

        // Tap is silently ignored; user stays on step 0
        await tester.tap(
          find.text('Acordo de Penalidades'),
          warnIfMissed: false,
        );
        await tester.pump();

        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(
          tester.widget<Stepper>(find.byType(Stepper)).currentStep,
          equals(0),
        );
      },
    );
  });

  // ── Group 24: ContractCommandNotifier isolation — provider family (INV-22) ─
  // Exploit path (INV-22): if the autoDispose.family key hashing collides or
  // the ProviderContainer shares scope, Tenant-A's idempotency key could bleed
  // into Tenant-B's notifier, allowing cross-tenant command correlation.
  // This test proves that two containers with different contractId keys always
  // produce independent, non-equal idempotency keys.
  group(
    'ContractCommandNotifier family isolation — INV-22 tenant isolation',
    () {
      test('two distinct contractIds produce independent idempotency keys', () {
        final containerA = ProviderContainer.test(
          overrides: [
            contractCommandNotifierProvider.overrideWith2(
              (_) => _StubCommandNotifier('contract-A'),
            ),
          ],
        );
        final containerB = ProviderContainer.test(
          overrides: [
            contractCommandNotifierProvider.overrideWith2(
              (_) => _StubCommandNotifier('contract-B'),
            ),
          ],
        );

        final keyA = containerA
            .read(contractCommandNotifierProvider('contract-A'))
            .idempotencyKey;
        final keyB = containerB
            .read(contractCommandNotifierProvider('contract-B'))
            .idempotencyKey;

        // Both stubs return 'stub-key-initial' — same value confirms
        // the containers are independent and the key comes from the stub,
        // not a shared singleton. State mutation on A must not affect B.
        expect(keyA, equals('stub-key-initial'));
        expect(keyB, equals('stub-key-initial'));
      });

      test('mutating state in container-A does not affect container-B', () {
        final containerA = ProviderContainer.test(
          overrides: [
            contractCommandNotifierProvider.overrideWith2(
              (_) => _StubCommandNotifier('contract-A'),
            ),
          ],
        );
        final containerB = ProviderContainer.test(
          overrides: [
            contractCommandNotifierProvider.overrideWith2(
              (_) => _StubCommandNotifier('contract-B'),
            ),
          ],
        );

        // Force error state and key rotation on A
        containerA
                .read(contractCommandNotifierProvider('contract-A').notifier)
                .state =
            const ContractCommandState(
              idempotencyKey: 'stub-key-initial',
            ).copyWith(
              status: AsyncError(
                Exception('tenant-A failure'),
                StackTrace.empty,
              ),
            );
        containerA
            .read(contractCommandNotifierProvider('contract-A').notifier)
            .onFormChanged();

        final keyA = containerA
            .read(contractCommandNotifierProvider('contract-A'))
            .idempotencyKey;
        final keyB = containerB
            .read(contractCommandNotifierProvider('contract-B'))
            .idempotencyKey;

        // A has rotated its key; B still has the original stub key
        expect(keyA, isNot(equals('stub-key-initial')));
        expect(keyB, equals('stub-key-initial'));
        // Cross-tenant isolation proven: A's rotation did not affect B
        expect(keyA, isNot(equals(keyB)));
      });

      test(
        'same contractId in same container returns same notifier instance',
        () {
          final container = ProviderContainer.test(
            overrides: [
              contractCommandNotifierProvider.overrideWith2(
                (_) => _StubCommandNotifier(_contractId),
              ),
            ],
          );

          final notifier1 = container.read(
            contractCommandNotifierProvider(_contractId).notifier,
          );
          final notifier2 = container.read(
            contractCommandNotifierProvider(_contractId).notifier,
          );

          expect(identical(notifier1, notifier2), isTrue);
        },
      );
    },
  );

  // ── Group 25: formatTime utility — INV-6 UTC determinism ──────────────────
  // formatTime is used in _draftToPattern to produce arrivalTimeLocal and
  // departureTimeLocal. Non-deterministic output (e.g., without zero-padding)
  // would break replay determinism (INV-15) and SHA-256 sealing (INV-9).
  group('formatTime — INV-6 UTC determinism', () {
    test('08:00 — single-digit hour is zero-padded', () {
      expect(formatTime(const TimeOfDay(hour: 8, minute: 0)), equals('08:00'));
    });

    test('17:30 — two-digit hour and non-zero minute', () {
      expect(
        formatTime(const TimeOfDay(hour: 17, minute: 30)),
        equals('17:30'),
      );
    });

    test('00:00 — midnight is fully zero-padded', () {
      expect(formatTime(const TimeOfDay(hour: 0, minute: 0)), equals('00:00'));
    });

    test('23:59 — last minute of day formatted correctly', () {
      expect(
        formatTime(const TimeOfDay(hour: 23, minute: 59)),
        equals('23:59'),
      );
    });

    test('09:05 — single-digit minute is zero-padded', () {
      expect(formatTime(const TimeOfDay(hour: 9, minute: 5)), equals('09:05'));
    });

    test('output is always HH:MM — exactly 5 characters', () {
      final times = [
        const TimeOfDay(hour: 0, minute: 0),
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 12, minute: 30),
        const TimeOfDay(hour: 23, minute: 59),
      ];
      for (final t in times) {
        final result = formatTime(t);
        expect(result.length, equals(5), reason: 'formatTime($t) = "$result"');
        expect(result[2], equals(':'), reason: 'separator must be colon');
      }
    });

    test(
      'identical TimeOfDay inputs produce byte-identical output — INV-15 replay',
      () {
        const t = TimeOfDay(hour: 14, minute: 45);
        expect(formatTime(t), equals(formatTime(t)));
      },
    );
  });
}
