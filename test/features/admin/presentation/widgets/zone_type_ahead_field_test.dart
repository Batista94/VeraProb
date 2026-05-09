import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/widgets/zone_type_ahead_field.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_operational_zone_repository.dart';

// ── Shared fixtures ───────────────────────────────────────────

const _kOrgId = 'org-test';

OperationalZoneView _makeZone(
  String name, {
  String? contractorId,
  GeofenceView? geofence,
  ZoneType type = ZoneType.garagem,
}) => OperationalZoneView(
  id: 'test-id-${name.hashCode}',
  organizationId: _kOrgId,
  name: name,
  type: type,
  contractorId: contractorId,
  geofence: geofence,
);

const _kGeo = GeofenceView(
  latitude: -23.5505,
  longitude: -46.6333,
  radiusMeters: 200,
);

// ── Test widget builder ───────────────────────────────────────

Widget _buildTestWidget({
  required List<OperationalZoneView> zones,
  OperationalZoneView? selectedZone,
  ValueChanged<OperationalZoneView?>? onChanged,
  ValueChanged<OperationalZoneView>? onGeofenceConfigured,
}) {
  final repository = InMemoryOperationalZoneRepository();
  return ProviderScope(
    overrides: [
      operationalZoneRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Consumer(
            builder: (context, ref, _) => ZoneTypeAheadField(
              label: 'Zona de Partida',
              prefixIcon: Icons.business,
              zones: zones,
              selectedZone: selectedZone,
              onInvalidateZones: () async =>
                  ref.invalidate(operationalZonesProvider),
              onChanged: onChanged ?? (_) {},
              onGeofenceConfigured: onGeofenceConfigured,
            ),
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────

void main() {
  // ── Unit tests: filterZones ───────────────────────────────

  group('filterZones', () {
    final zones = [
      _makeZone('Garagem Central'),
      _makeZone('Portaria Sul'),
      _makeZone('Apoio Leste'),
    ];

    test('query vazia retorna todas as zonas', () {
      final result = filterZones(zones, '');
      expect(result, equals(zones));
    });

    test('filtra por substring case-insensitive (minúscula)', () {
      final result = filterZones(zones, 'gar');
      expect(result.length, 1);
      expect(result.first.name, 'Garagem Central');
    });

    test('filtra por substring case-insensitive (maiúscula)', () {
      final result = filterZones(zones, 'SUL');
      expect(result.length, 1);
      expect(result.first.name, 'Portaria Sul');
    });

    test('sem match retorna lista vazia', () {
      final result = filterZones(zones, 'xxxyyy');
      expect(result, isEmpty);
    });

    test('preserva a ordem do input (sort é responsabilidade do pai)', () {
      final result = filterZones(zones, 'a');
      expect(
        result.map((z) => z.name).toList(),
        containsAllInOrder(['Garagem Central', 'Portaria Sul', 'Apoio Leste']),
      );
    });

    test('zona global (sem contractorId) é visível', () {
      final shared = _makeZone('Zona Compartilhada');
      expect(shared.scope, ZoneScope.global);
      final result = filterZones([shared], '');
      expect(result, contains(shared));
    });

    test('zona exclusive (com contractorId) é incluída na lista completa', () {
      final zone = _makeZone('Garagem ACME', contractorId: 'contractor-uuid');
      expect(zone.scope, ZoneScope.exclusive);
      final result = filterZones([zone], '');
      expect(result, contains(zone));
    });
  });

  // ── Widget tests ──────────────────────────────────────────

  group('ZoneTypeAheadField widget', () {
    testWidgets('renderiza com o label correto', (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));
      expect(find.text('Zona de Partida'), findsOneWidget);
    });

    testWidgets(
      'mostra sufixo location_on quando zona selecionada tem geofence',
      (tester) async {
        final zone = _makeZone('Garagem', geofence: _kGeo);
        await tester.pumpWidget(
          _buildTestWidget(zones: [zone], selectedZone: zone),
        );
        expect(find.byIcon(Icons.location_on), findsOneWidget);
      },
    );

    testWidgets(
      'mostra sufixo location_off quando zona selecionada não tem geofence',
      (tester) async {
        final zone = _makeZone('Garagem');
        await tester.pumpWidget(
          _buildTestWidget(zones: [zone], selectedZone: zone),
        );
        expect(find.byIcon(Icons.location_off), findsOneWidget);
      },
    );

    testWidgets(
      'botão "Configurar Geofence" aparece quando zona selecionada não tem geofence',
      (tester) async {
        final zone = _makeZone('Garagem');
        await tester.pumpWidget(
          _buildTestWidget(zones: [zone], selectedZone: zone),
        );
        expect(find.text('Configurar Geofence →'), findsOneWidget);
      },
    );

    testWidgets(
      'botão "Configurar Geofence" não aparece quando geofence configurado',
      (tester) async {
        final zone = _makeZone('Garagem', geofence: _kGeo);
        await tester.pumpWidget(
          _buildTestWidget(zones: [zone], selectedZone: zone),
        );
        expect(find.text('Configurar Geofence →'), findsNothing);
      },
    );

    // ── "+ Criar" button ──────────────────────────────────────

    testWidgets(
      'botão "+ Criar nova zona" aparece quando campo está vazio e lista vazia',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget(zones: []));
        expect(find.text('+ Criar nova zona'), findsOneWidget);
      },
    );

    testWidgets(
      'botão "+ Criar zona X" aparece após digitar nome inexistente',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget(zones: []));

        await tester.enterText(find.byType(TextFormField), 'Garagem Norte');
        await tester.pump();

        expect(find.text('+ Criar zona "Garagem Norte"'), findsOneWidget);
      },
    );

    testWidgets(
      'botão "+ Criar" não aparece quando texto corresponde exatamente a zona existente',
      (tester) async {
        final zone = _makeZone('Garagem Sul', geofence: _kGeo);
        await tester.pumpWidget(_buildTestWidget(zones: [zone]));

        await tester.enterText(find.byType(TextFormField), 'Garagem Sul');
        await tester.pump();

        expect(find.textContaining('+ Criar'), findsNothing);
      },
    );

    testWidgets('selecionar zona existente chama onChanged', (tester) async {
      final zone = _makeZone('Portaria Norte', geofence: _kGeo);
      OperationalZoneView? selected;

      await tester.pumpWidget(
        _buildTestWidget(zones: [zone], onChanged: (z) => selected = z),
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'Portaria');
      await tester.pump();

      await tester.tap(find.text('Portaria Norte'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.name, 'Portaria Norte');
    });

    testWidgets(
      'exibe botão de limpar (X) quando zona está selecionada e limpa ao clicar',
      (tester) async {
        final zone = _makeZone('Garagem', geofence: _kGeo);
        OperationalZoneView? selected = zone;

        await tester.pumpWidget(
          _buildTestWidget(
            zones: [zone],
            selectedZone: selected,
            onChanged: (z) => selected = z,
          ),
        );

        expect(find.byIcon(Icons.clear), findsOneWidget);

        await tester.tap(find.byIcon(Icons.clear));
        await tester.pump();

        expect(selected, isNull);

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.controller?.text, isEmpty);
      },
    );
  });
}
