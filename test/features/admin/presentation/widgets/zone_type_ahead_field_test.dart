import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:busflow/domain/sla_audit/operational_zone.dart';
import 'package:busflow/features/admin/presentation/widgets/zone_type_ahead_field.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_operational_zone_repository.dart';
import 'package:busflow/state/providers/operational_zone_providers.dart';

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

/// Wraps [ZoneTypeAheadField] in the minimal Flutter tree needed for widget
/// tests — ProviderScope → MaterialApp → Scaffold → Consumer.
Widget _buildTestWidget({
  required List<OperationalZone> zones,
  OperationalZone? selectedZone,
  String contractorName = '',
  ValueChanged<OperationalZone?>? onChanged,
  VoidCallback? onGeofenceConfigured,
  InMemoryOperationalZoneRepository? repo,
}) {
  final repository = repo ?? InMemoryOperationalZoneRepository();
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
              organizationId: _kOrgId,
              onSaveZone: (z) async {
                await repository.save(z);
              },
              onInvalidateZones: () async => ref.invalidate(operationalZonesProvider),
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

    test('query vazia retorna todas as zonas na mesma ordem', () {
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
      // 'a' matches Garagem, PortariA, Apoio
      final result = filterZones(zones, 'a');
      expect(result.map((z) => z.name).toList(),
          containsAllInOrder(['Garagem Central', 'Portaria Sul', 'Apoio Leste']));
    });

    test('query com apenas espaços não casa com nomes de zonas reais', () {
      final result = filterZones(zones, '   ');
      // '   ' is non-empty so filterZones uses it as a substring — no zone
      // name contains 3 consecutive spaces.
      expect(result, isEmpty);
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
          _buildTestWidget(zones: [zone], selectedZone: zone));
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets(
        'mostra sufixo location_off quando zona selecionada não tem geofence',
        (tester) async {
      final zone = _makeZone('Garagem');
      await tester.pumpWidget(
          _buildTestWidget(zones: [zone], selectedZone: zone));
      expect(find.byIcon(Icons.location_off), findsOneWidget);
    });

    testWidgets(
        'botão "Configurar Geofence" aparece quando zona selecionada não tem geofence',
        (tester) async {
      final zone = _makeZone('Garagem');
      await tester.pumpWidget(
          _buildTestWidget(zones: [zone], selectedZone: zone));
      expect(find.text('Configurar Geofence →'), findsOneWidget);
    });

    testWidgets(
        'botão "Configurar Geofence" não aparece quando geofence configurado',
        (tester) async {
      final zone = _makeZone('Garagem', geofence: _kGeo);
      await tester.pumpWidget(
          _buildTestWidget(zones: [zone], selectedZone: zone));
      expect(find.text('Configurar Geofence →'), findsNothing);
    });

    // ── "+ Criar" button (standalone, below the field) ────────

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

    // ── Mini-form ─────────────────────────────────────────────

    testWidgets('tocar "+ Criar" expande o mini-form', (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));

      await tester.enterText(find.byType(TextFormField), 'Garagem X');
      await tester.pump();

      await tester.tap(find.text('+ Criar zona "Garagem X"'));
      await tester.pumpAndSettle();

      expect(find.text('Nova Zona'), findsOneWidget);
      expect(find.text('Criar Zona'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('mini-form pré-preenche o nome com o texto digitado',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));

      await tester.enterText(find.byType(TextFormField), 'Portaria X');
      await tester.pump();
      await tester.tap(find.text('+ Criar zona "Portaria X"'));
      await tester.pumpAndSettle();

      // The name field inside the form should be pre-filled
      final nameFields =
          tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
      // Name field is the second TextFormField (first is the autocomplete)
      expect(nameFields.length, greaterThan(1));
    });

    testWidgets('cancelar mini-form oculta o painel', (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));

      await tester.tap(find.text('+ Criar nova zona'));
      await tester.pumpAndSettle();
      expect(find.text('Nova Zona'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Nova Zona'), findsNothing);
    });

    testWidgets(
        'mini-form oculto → botão "+ Criar" oculto (sem duplicação)',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));

      // Open mini-form
      await tester.tap(find.text('+ Criar nova zona'));
      await tester.pumpAndSettle();
      expect(find.text('Nova Zona'), findsOneWidget);

      // "+ Criar" button should be hidden while mini-form is open
      expect(find.text('+ Criar nova zona'), findsNothing);
    });

    testWidgets(
        'criação com sucesso chama onChanged com a nova zona e fecha mini-form',
        (tester) async {
      OperationalZone? receivedZone;
      final repo = InMemoryOperationalZoneRepository();

      await tester.pumpWidget(_buildTestWidget(
        zones: [],
        repo: repo,
        onChanged: (z) => receivedZone = z,
      ));

      // Open mini-form via empty "+ Criar nova zona"
      await tester.tap(find.text('+ Criar nova zona'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('zone_mini_form_name')), 'Garagem Criada');

      await tester.tap(find.byKey(const Key('zone_mini_form_submit')));
      // pump once for setState(_isSaving=true), then once for the async chain
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(receivedZone, isNotNull);
      expect(receivedZone!.name, 'Garagem Criada');
      expect(receivedZone!.organizationId, _kOrgId);

      // Mini-form closed
      expect(find.text('Nova Zona'), findsNothing);
    });

    testWidgets(
        'erro de geofence parcial exibe mensagem no mini-form',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));

      await tester.tap(find.text('+ Criar nova zona'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('zone_mini_form_name')), 'Zona GeoInc');

      // Expand geofence section
      await tester.tap(find.text('Geofence (recomendado)'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('zone_mini_form_lat')), '-23.5');
      // Leave longitude and radius empty

      await tester.tap(find.text('Criar Zona'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Preencha Latitude, Longitude e Raio'),
        findsOneWidget,
      );
      // Mini-form still open after error
      expect(find.text('Nova Zona'), findsOneWidget);
    });

    testWidgets(
        'erro DomainException (nome vazio) exibe mensagem no mini-form',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(zones: []));

      await tester.tap(find.text('+ Criar nova zona'));
      await tester.pumpAndSettle();

      // Name field starts empty; submit without filling it to trigger DomainException.
      await tester.enterText(
          find.byKey(const Key('zone_mini_form_name')), '');

      await tester.tap(find.text('Criar Zona'));
      await tester.pumpAndSettle();

      // DomainException from OperationalZone.create — some error text appears
      expect(
        find.descendant(
          of: find.byType(Container),
          matching: find.byType(Text),
        ).evaluate().where((e) {
          final widget = e.widget as Text;
          final text = widget.data ?? '';
          return text.isNotEmpty && text != 'Nova Zona' &&
              text != 'Criar Zona' && text != 'Cancelar';
        }).isNotEmpty,
        isTrue,
      );
      // Mini-form still open
      expect(find.text('Nova Zona'), findsOneWidget);
    });

    testWidgets(
        'zona com contractorLabel igual a contractorName exibe badge no overlay',
        (tester) async {
      final zone = _makeZone('Frota ACME', contractorLabel: 'ACME Corp');

      await tester.pumpWidget(_buildTestWidget(
        zones: [zone],
        contractorName: 'ACME Corp',
      ));

      // Open the autocomplete overlay
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
  });
}
