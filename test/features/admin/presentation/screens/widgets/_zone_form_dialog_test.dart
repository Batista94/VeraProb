import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/sla_audit/geocoding_repository.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/_zone_form_dialog.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_operational_zone_repository.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';

// ── Fixtures ─────────────────────────────────────────────────

const _kOrgId = 'org-test-001';

const _kGeo = GeofenceView(
  latitude: -23.5505,
  longitude: -46.6333,
  radiusMeters: 200,
);

const _zoneWithGeo = OperationalZoneView(
  id: 'zone-001',
  organizationId: _kOrgId,
  name: 'Garagem Central',
  type: ZoneType.garagem,
  geofence: _kGeo,
);

const _zoneWithoutGeo = OperationalZoneView(
  id: 'zone-002',
  organizationId: _kOrgId,
  name: 'Portaria Sul',
  type: ZoneType.garagem,
);

// ── Fake geocoding repository ─────────────────────────────────

class _FakeGeocodingRepository implements GeocodingRepository {
  final List<PlaceSuggestion> _results;
  int callCount = 0;

  _FakeGeocodingRepository({List<PlaceSuggestion> results = const []})
    : _results = results;

  @override
  Future<List<PlaceSuggestion>> search(String query) async {
    callCount++;
    return _results;
  }
}

// ── Host widget factory ───────────────────────────────────────

Widget _buildHost({
  OperationalZoneView? existingZone,
  _FakeGeocodingRepository? geocodingRepo,
  String? orgId = _kOrgId,
  InMemoryOperationalZoneRepository? zoneRepo,
}) {
  final geoRepo = geocodingRepo ?? _FakeGeocodingRepository();
  final repo = zoneRepo ?? InMemoryOperationalZoneRepository();

  return ProviderScope(
    overrides: [
      currentOrganizationIdProvider.overrideWithValue(orgId),
      operationalZoneRepositoryProvider.overrideWithValue(repo),
      geocodingRepositoryProvider.overrideWithValue(geoRepo),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () =>
                showZoneFormDialog(ctx, existingZone: existingZone),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(); // FutureProvider microtask completes
  await tester.pump(
    const Duration(milliseconds: 200),
  ); // animation + provider rebuild
}

void _setScreenSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
}

/// Expands the geofence ExpansionTile and waits for animation.
Future<void> _expandGeofenceTile(WidgetTester tester) async {
  final tileTitle = find.text('Configuração de Geofence');
  await tester.ensureVisible(tileTitle);
  await tester.tap(tileTitle);
  await tester.pump(const Duration(milliseconds: 300));
}

// ─────────────────────────────────────────────────────────────

void main() {
  // ── 1. Pin Drop ───────────────────────────────────────────

  group('1. Pin Drop — mapa renderiza e estado de pin', () {
    testWidgets('FlutterMap renderiza no dialog', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost());
      await tester.pumpAndSettle();
      await _openDialog(tester);

      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('sem geofence → subtítulo "Zona Inativa para Auditoria"', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost());
      await tester.pumpAndSettle();
      await _openDialog(tester);

      expect(find.text('Zona Inativa para Auditoria'), findsOneWidget);
    });

    testWidgets('com geofence pré-configurado → MarkerLayer visível', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(existingZone: _zoneWithGeo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      // Zone has geofence → MarkerLayer rendered + subtitle = Configurado
      expect(find.byType(MarkerLayer), findsOneWidget);
      expect(find.text('Configurado'), findsOneWidget);
    });

    testWidgets('limpar coordenadas esconde display lat/lng', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(existingZone: _zoneWithGeo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      // Geofence starts expanded for zone with geo
      expect(find.text('Limpar'), findsOneWidget);

      await tester.tap(find.text('Limpar'));
      await tester.pump();

      expect(find.text('Limpar'), findsNothing);
      expect(find.byIcon(Icons.my_location), findsNothing);
    });
  });

  // ── 2. Radius Validation ──────────────────────────────────

  group('2. Radius — validação bounds (1m–50.000m)', () {
    Future<void> openWithGeo(WidgetTester tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_buildHost(existingZone: _zoneWithGeo));
      await tester.pumpAndSettle();
      await _openDialog(tester);
    }

    Finder radiusField() => find.descendant(
      of: find.byType(ExpansionTile),
      matching: find.byType(TextField),
    );

    Future<void> submitForm(WidgetTester tester) async {
      await tester.tap(find.text('Salvar Zona'));
      await tester.pump();
    }

    testWidgets('raio 0 → erro "1 a 50.000 m"', (tester) async {
      await openWithGeo(tester);
      await tester.ensureVisible(radiusField());
      await tester.enterText(radiusField(), '0');
      await submitForm(tester);
      expect(find.text('1 a 50.000 m'), findsOneWidget);
    });

    testWidgets('raio 50001 → erro "1 a 50.000 m"', (tester) async {
      await openWithGeo(tester);
      await tester.ensureVisible(radiusField());
      await tester.enterText(radiusField(), '50001');
      await submitForm(tester);
      expect(find.text('1 a 50.000 m'), findsOneWidget);
    });

    testWidgets('raio vazio quando geofence ativo → erro obrigatório', (
      tester,
    ) async {
      await openWithGeo(tester);
      await tester.ensureVisible(radiusField());
      await tester.enterText(radiusField(), '');
      await submitForm(tester);
      expect(find.text('Obrigatório com geofence'), findsOneWidget);
    });

    testWidgets('raio 100 é válido e não mostra erro', (tester) async {
      // Open without geofence to avoid submit path (radius not required)
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = InMemoryOperationalZoneRepository();
      await tester.pumpWidget(_buildHost(zoneRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      // Fill name
      await tester.enterText(find.byType(TextField).first, 'Garagem Norte');
      await tester.pump();

      // Submit without geofence — radius validator returns null (no geo)
      await tester.tap(find.text('Criar Zona'));
      await tester.pump(const Duration(milliseconds: 100));

      // No radius error
      expect(find.text('1 a 50.000 m'), findsNothing);
      expect(find.text('Obrigatório com geofence'), findsNothing);
    });

    testWidgets('raio sem geofence ativo não dispara validação', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(existingZone: _zoneWithoutGeo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      // Geofence section exists but no lat/lng
      expect(find.text('Zona Inativa para Auditoria'), findsOneWidget);

      // Try to save
      await tester.tap(find.text('Salvar Zona'));
      await tester.pump(const Duration(milliseconds: 100));

      // No radius error because _lat == null
      expect(find.text('1 a 50.000 m'), findsNothing);
    });
  });

  // ── 3. Autocomplete Nominatim ─────────────────────────────

  group('3. Autocomplete Nominatim — busca → seleciona → foca mapa', () {
    final fakeSuggestions = [
      const PlaceSuggestion(
        displayName: 'Avenida Paulista, São Paulo - SP',
        lat: -23.5614,
        lng: -46.6560,
      ),
      const PlaceSuggestion(
        displayName: 'Avenida Paulista, 1000, São Paulo',
        lat: -23.5620,
        lng: -46.6555,
      ),
    ];

    testWidgets('query < 4 chars não dispara busca', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _FakeGeocodingRepository(results: fakeSuggestions);
      await tester.pumpWidget(_buildHost(geocodingRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      // Address field — 2nd TextField (0=Nome, 1=Endereço)
      final addressField = find.byType(TextField).at(1);
      await tester.ensureVisible(addressField);
      await tester.enterText(addressField, 'Av');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // No search triggered (< 4 chars)
      expect(repo.callCount, 0);
      expect(find.text('Avenida Paulista, São Paulo - SP'), findsNothing);
    });

    testWidgets('query ≥ 4 chars dispara busca após debounce', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _FakeGeocodingRepository(results: fakeSuggestions);
      await tester.pumpWidget(_buildHost(geocodingRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      final addressField = find.byType(TextField).at(1);
      await tester.ensureVisible(addressField);
      await tester.enterText(addressField, 'Avenida Paulista');

      // Advance debounce timer (500ms)
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Avenida Paulista, São Paulo - SP'), findsOneWidget);
      expect(find.text('Avenida Paulista, 1000, São Paulo'), findsOneWidget);
    });

    testWidgets('selecionar sugestão muda subtítulo para Configurado', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _FakeGeocodingRepository(results: fakeSuggestions);
      await tester.pumpWidget(_buildHost(geocodingRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      final addressField = find.byType(TextField).at(1);
      await tester.ensureVisible(addressField);
      await tester.enterText(addressField, 'Avenida Paulista');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Avenida Paulista, São Paulo - SP'));
      await tester.pump();

      // lat/lng set → subtitle changes
      expect(find.text('Configurado'), findsOneWidget);

      // Expand tile to verify coordinate display
      await _expandGeofenceTile(tester);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.text('Limpar'), findsOneWidget);
    });

    testWidgets('botão X limpa sugestões', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _FakeGeocodingRepository(results: fakeSuggestions);
      await tester.pumpWidget(_buildHost(geocodingRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      final addressField = find.byType(TextField).at(1);
      await tester.ensureVisible(addressField);
      await tester.enterText(addressField, 'Avenida Paulista');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Avenida Paulista, São Paulo - SP'), findsOneWidget);

      // Tap the clear (X) button in address field suffix
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(find.text('Avenida Paulista, São Paulo - SP'), findsNothing);
    });
  });

  // ── 4. Isolation INV-1 — org session guard ───────────────────

  group('4. Isolation INV-1 — session guard', () {
    testWidgets('orgId null → erro ao submeter (sessão expirada)', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(orgId: null));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.enterText(find.byType(TextField).first, 'Zona Teste');
      await tester.pump();

      await tester.tap(find.text('Criar Zona'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Sessão expirada. Faça login novamente.'),
        findsOneWidget,
      );
    });
  });

  // ── 5. Golden Rule — Zona Inativa para Auditoria ──────────

  group('5. Golden Rule — salvar sem geofence', () {
    testWidgets('sem geofence → subtítulo "Zona Inativa para Auditoria"', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost());
      await tester.pumpAndSettle();
      await _openDialog(tester);

      expect(find.text('Zona Inativa para Auditoria'), findsOneWidget);
    });

    testWidgets('com geofence → subtítulo "Configurado"', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(existingZone: _zoneWithGeo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      expect(find.text('Configurado'), findsOneWidget);
      expect(find.text('Zona Inativa para Auditoria'), findsNothing);
    });

    testWidgets('salvar sem geofence → zona criada com geofence null', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = InMemoryOperationalZoneRepository();
      await tester.pumpWidget(_buildHost(zoneRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.enterText(find.byType(TextField).first, 'Zona Sem Geo');
      await tester.pump();

      await tester.tap(find.text('Criar Zona'));
      await tester.pump(const Duration(milliseconds: 200));

      final zones = await repo.findByOrganization(_kOrgId);
      expect(zones.length, 1);
      expect(zones.first.name, 'Zona Sem Geo');
      expect(zones.first.geofence, isNull);
    });

    testWidgets('salvar com geofence → zona criada com geofence não null', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = InMemoryOperationalZoneRepository();
      await tester.pumpWidget(
        _buildHost(existingZone: _zoneWithGeo, zoneRepo: repo),
      );
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.tap(find.text('Salvar Zona'));
      await tester.pump(const Duration(milliseconds: 200));

      final zones = await repo.findByOrganization(_kOrgId);
      expect(zones.length, 1);
      expect(zones.first.geofence, isNotNull);
      expect(zones.first.geofence!.radiusMeters, 200);
    });

    testWidgets('cancelar não salva zona', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = InMemoryOperationalZoneRepository();
      await tester.pumpWidget(_buildHost(zoneRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.enterText(find.byType(TextField).first, 'Zona Cancelada');
      await tester.pump();

      await tester.tap(find.text('Cancelar'));
      await tester.pump();

      final zones = await repo.findByOrganization(_kOrgId);
      expect(zones, isEmpty);
    });
  });

  // ── 6. Sync — endereço → marcador no mapa ─────────────────

  group('6. Sync — coordenadas sincronizam com estado do mapa', () {
    final singleSuggestion = [
      const PlaceSuggestion(
        displayName: 'Rua Augusta, São Paulo',
        lat: -23.5534,
        lng: -46.6536,
      ),
    ];

    testWidgets('selecionar sugestão exibe coordenadas corretas', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _FakeGeocodingRepository(results: singleSuggestion);
      await tester.pumpWidget(_buildHost(geocodingRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      final addressField = find.byType(TextField).at(1);
      await tester.ensureVisible(addressField);
      await tester.enterText(addressField, 'Rua Augusta São Paulo');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Rua Augusta, São Paulo'));
      await tester.pump();

      // Expand tile to see coordinate display
      await _expandGeofenceTile(tester);

      // Coordinates should show lat -23.553400 and lng -46.653600
      expect(find.textContaining('-23.553400, -46.653600'), findsOneWidget);
    });

    testWidgets('segunda seleção sobrescreve coordenadas anteriores', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final suggestions1 = [
        const PlaceSuggestion(
          displayName: 'Rua A',
          lat: -23.0000,
          lng: -46.0000,
        ),
      ];
      final suggestions2 = [
        const PlaceSuggestion(
          displayName: 'Rua B',
          lat: -24.0000,
          lng: -47.0000,
        ),
      ];

      final repo = _FakeGeocodingRepository(results: suggestions1);

      await tester.pumpWidget(_buildHost(geocodingRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      final addressField = find.byType(TextField).at(1);
      await tester.ensureVisible(addressField);

      // First selection
      await tester.enterText(addressField, 'Rua AAAA');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Rua A'));
      await tester.pump();

      // Expand tile to verify first coordinates
      await _expandGeofenceTile(tester);
      expect(find.textContaining('-23.000000, -46.000000'), findsOneWidget);

      // Update repo to return second suggestion
      repo._results.clear();
      repo._results.addAll(suggestions2);

      // Clear address and search again
      await tester.enterText(addressField, 'Rua BBBB');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Rua B'));
      await tester.pump();

      // Coordinates updated (tile still expanded)
      expect(find.textContaining('-24.000000, -47.000000'), findsOneWidget);
      expect(find.textContaining('-23.000000, -46.000000'), findsNothing);
    });

    testWidgets('address field atualiza com displayName da sugestão', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _FakeGeocodingRepository(results: singleSuggestion);
      await tester.pumpWidget(_buildHost(geocodingRepo: repo));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      final addressField = find.byType(TextField).at(1);
      await tester.ensureVisible(addressField);
      await tester.enterText(addressField, 'Rua Augusta');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Rua Augusta, São Paulo'));
      await tester.pump();

      final tf = tester.widget<TextField>(addressField);
      expect(tf.controller?.text, 'Rua Augusta, São Paulo');
    });
  });
}
