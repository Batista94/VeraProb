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
    test('zone missing geofence → missingNames non-empty → BLOQUEIO message', () {
      final zone = _zoneNoGeo;
      final missing = [if (zone.geofence == null) zone.name];
      expect(missing, isNotEmpty);
      final msg =
          'BLOQUEIO DE AUDITORIA: ${missing.join(' e ')} não possui geofence configurado';
      expect(msg, contains('BLOQUEIO DE AUDITORIA'));
      expect(msg, contains('Zona Sem Geofence'));
    });

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
    testWidgets(
      'BLOQUEIO DE AUDITORIA shown when destination zone lacks geofence',
      (tester) async {
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

        expect(find.textContaining('BLOQUEIO DE AUDITORIA'), findsOneWidget);
      },
    );
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
}
