import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pactaflow/domain/sla_audit/operational_zone.dart';
import 'package:pactaflow/features/admin/presentation/widgets/zone_type_ahead_field.dart';
import 'package:pactaflow/state/providers/operational_zone_providers.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_operational_zone_repository.dart';

// ── Shared fixtures ───────────────────────────────────────────

const _kOrgId = 'org-test';

OperationalZone _makeZone(
  String name, {
  String? contractorLabel,
  GeofenceConfiguration? geofence,
  ZoneType type = ZoneType.garagem,
}) =>
    OperationalZone.create(
      organizationId: _kOrgId,
      name: name,
      type: type,
      contractorLabel: contractorLabel,
      geofence: geofence,
    );

const _kGeo = GeofenceConfiguration(
  latitude: -23.5505,
  longitude: -46.6333,
  radiusMeters: 200,
);

// ── Test widget builder ───────────────────────────────────────

Widget _buildTestWidget({
  required List<OperationalZone> zones,
  OperationalZone? selectedZone,
  String contractorName = '',
  ValueChanged<OperationalZone?>? onChanged,
  ValueChanged<OperationalZone>? onGeofenceConfigured,
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
              contractorName: contractorName,
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

    test('query vazia retorna todas as zonas sem label', () {
      final result = filterZones(zones, '', 'qualquer');
      expect(result, equals(zones));
    });

    test('filtra por substring case-insensitive (minúscula)', () {
      final result = filterZones(zones, 'gar', '');
      expect(result.length, 1);
      expect(result.first.name, 'Garagem Central');
    });

    test('filtra por substring case-insensitive (maiúscula)', () {
      final result = filterZones(zones, 'SUL', '');
      expect(result.length, 1);
      expect(result.first.name, 'Portaria Sul');
    });

    test('sem match retorna lista vazia', () {
      final result = filterZones(zones, 'xxxyyy', '');
      expect(result, isEmpty);
    });

    test('preserva a ordem do input (sort é responsabilidade do pai)', () {
      final result = filterZones(zones, 'a', '');
      expect(result.map((z) => z.name).toList(),
          containsAllInOrder(['Garagem Central', 'Portaria Sul', 'Apoio Leste']));
    });

    test('ZoneScope.global (sem contractorLabel) é visível para qualquer contratante', () {
      final shared = _makeZone('Zona Compartilhada');
      expect(shared.scope, ZoneScope.global);
      final result = filterZones([shared], '', 'ACME');
      expect(result, contains(shared));
    });

    test('ZoneScope.exclusive de outro contratante é excluída', () {
      final zoneAcme = _makeZone('Garagem ACME', contractorLabel: 'ACME Corp');
      final zoneOther =
          _makeZone('Portaria Beta', contractorLabel: 'Beta Ltda');
      expect(zoneAcme.scope, ZoneScope.exclusive);
      expect(zoneOther.scope, ZoneScope.exclusive);
      final result = filterZones([zoneAcme, zoneOther], '', 'ACME Corp');
      expect(result.map((z) => z.name), contains('Garagem ACME'));
      expect(result.map((z) => z.name), isNot(contains('Portaria Beta')));
    });

    test('ZoneScope.exclusive do contratante correto é incluída', () {
      final zone = _makeZone('Garagem ACME', contractorLabel: 'ACME Corp');
      expect(zone.scope, ZoneScope.exclusive);
      final result = filterZones([zone], '', 'ACME Corp');
      expect(result, contains(zone));
    });

    test('filtro de contratante + substring name combinados', () {
      final z1 = _makeZone('Portaria ACME', contractorLabel: 'ACME Corp');
      final z2 = _makeZone('Portaria Beta', contractorLabel: 'Beta Ltda');
      final result = filterZones([z1, z2], 'portaria', 'ACME Corp');
      expect(result.length, 1);
      expect(result.first.name, 'Portaria ACME');
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
      await tester
          .pumpWidget(_buildTestWidget(zones: [zone], selectedZone: zone));
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets(
        'mostra sufixo location_off quando zona selecionada não tem geofence',
        (tester) async {
      final zone = _makeZone('Garagem');
      await tester
          .pumpWidget(_buildTestWidget(zones: [zone], selectedZone: zone));
      expect(find.byIcon(Icons.location_off), findsOneWidget);
    });

    testWidgets(
        'botão "Configurar Geofence" aparece quando zona selecionada não tem geofence',
        (tester) async {
      final zone = _makeZone('Garagem');
      await tester
          .pumpWidget(_buildTestWidget(zones: [zone], selectedZone: zone));
      expect(find.text('Configurar Geofence →'), findsOneWidget);
    });

    testWidgets(
        'botão "Configurar Geofence" não aparece quando geofence configurado',
        (tester) async {
      final zone = _makeZone('Garagem', geofence: _kGeo);
      await tester
          .pumpWidget(_buildTestWidget(zones: [zone], selectedZone: zone));
      expect(find.text('Configurar Geofence →'), findsNothing);
    });

    // ── "+ Criar" button ──────────────────────────────────────

    testWidgets(
        'botão "+ Criar nova zona" aparece quando campo está vazio e lista vazia',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));
      expect(find.text('+ Criar nova zona'), findsOneWidget);
    });

    testWidgets(
        'botão "+ Criar zona X" aparece após digitar nome inexistente',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));

      await tester.enterText(find.byType(TextFormField), 'Garagem Norte');
      await tester.pump();

      expect(find.text('+ Criar zona "Garagem Norte"'), findsOneWidget);
    });

    testWidgets(
        'botão "+ Criar" não aparece quando texto corresponde exatamente a zona existente',
        (tester) async {
      final zone = _makeZone('Garagem Sul', geofence: _kGeo);
      await tester.pumpWidget(_buildTestWidget(zones: [zone]));

      await tester.enterText(find.byType(TextFormField), 'Garagem Sul');
      await tester.pump();

      expect(find.textContaining('+ Criar'), findsNothing);
    });

    testWidgets(
        'zona com contractorLabel igual a contractorName exibe badge no overlay',
        (tester) async {
      final zone = _makeZone('Frota ACME', contractorLabel: 'ACME Corp');

      await tester.pumpWidget(_buildTestWidget(
        zones: [zone],
        contractorName: 'ACME Corp',
      ));

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'ACME');
      await tester.pump();

      expect(find.text('Seu contratante'), findsOneWidget);
    });

    testWidgets('selecionar zona existente chama onChanged', (tester) async {
      final zone = _makeZone('Portaria Norte', geofence: _kGeo);
      OperationalZone? selected;

      await tester.pumpWidget(_buildTestWidget(
        zones: [zone],
        onChanged: (z) => selected = z,
      ));

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
        'zona de outro contratante não aparece no overlay',
        (tester) async {
      final zoneAcme =
          _makeZone('Garagem ACME', contractorLabel: 'ACME Corp', geofence: _kGeo);
      final zoneBeta =
          _makeZone('Portaria Beta', contractorLabel: 'Beta Ltda', geofence: _kGeo);

      await tester.pumpWidget(_buildTestWidget(
        zones: [zoneAcme, zoneBeta],
        contractorName: 'ACME Corp',
      ));

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'a');
      await tester.pump();

      expect(find.text('Garagem ACME'), findsOneWidget);
      expect(find.text('Portaria Beta'), findsNothing);
    });

    testWidgets('exibe botão de limpar (X) quando zona está selecionada e limpa ao clicar', (tester) async {
      final zone = _makeZone('Garagem', geofence: _kGeo);
      OperationalZone? selected = zone;

      await tester.pumpWidget(_buildTestWidget(
        zones: [zone],
        selectedZone: selected,
        onChanged: (z) => selected = z,
      ));

      // Verifica se o ícone de limpar está presente
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // Clica no botão de limpar
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      // Verifica se onChanged foi chamado com null
      expect(selected, isNull);
      
      // Verifica se o texto do controller foi limpo (implicitamente pelo pump se o controller for re-renderizado ou se verificarmos o TextField)
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);
    });
  });
}
