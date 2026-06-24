import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/features/dispute_portal/presentation/widgets/dispute_context_card.dart';

void main() {
  group('DisputeContextCard', () {
    testWidgets('renders correct Medido/Limite/Excesso text values', (
      WidgetTester tester,
    ) async {
      final contextData = InfractionContextProjection(
        status: 'disputed',
        recordId: 'test-record-id',
        assetIdentifier: 'TST-0001',
        orgDisplayName: 'Org Alpha',
        orgCnpj: '78.423.287/0001-50',
        orgLogoUrl: '',
        locationLabel: 'Rua Teste, 1',
        occurredAtUtc: DateTime.utc(2026, 6, 19, 20, 2),
        penaltyValueCents: 150000,
        // measured = ROUND(threshold + delta) = ROUND(80 + 8.5) = 89
        // exceeded = ROUND(delta) = ROUND(8.5) = 9
        // These are the values the fixed RPC returns; NOT delta_value (9) and delta-threshold (-71).
        measuredValue: 89,
        thresholdValue: 80,
        exceededBy: 9,
        clauseRef: 'VEL-01',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DisputeContextCard(contextData: contextData)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('89 km/h'), findsOneWidget);
      expect(find.text('80 km/h'), findsOneWidget);
      expect(find.text('+9 km/h'), findsOneWidget);
    });

    testWidgets('does not overflow when recordId is very long', (
      WidgetTester tester,
    ) async {
      // Cria projeção com um ID de registro muito longo
      final contextData = InfractionContextProjection(
        status: 'disputed',
        recordId: 'req_aaaa_aaaa_aaaa_aaaa_aaaa_aaaa_aaaa_aaaa_aaaa_aaaa_aaaa',
        assetIdentifier: 'VTR-001',
        orgDisplayName: 'Test Org',
        orgCnpj: '00.000.000/0001-00',
        orgLogoUrl: 'https://example.com/logo.png',
        locationLabel: 'Rodovia BR-116 Km 42',
        occurredAtUtc: DateTime.utc(2026, 3, 1, 10, 0),
        penaltyValueCents: 50000, // R$ 500,00
        measuredValue: 95,
        thresholdValue: 80,
        exceededBy: 15,
      );

      // Renderiza em um container de 320px (Narrow Panel Layout Lesson 3)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: DisputeContextCard(contextData: contextData),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Expect to find the widget without RenderFlex overflow exceptions.
      // If there was an overflow, tester.takeException() would catch it or pumpAndSettle would fail.
      expect(tester.takeException(), isNull);

      // Verify we render the card
      expect(find.byType(DisputeContextCard), findsOneWidget);
    });
  });
}
