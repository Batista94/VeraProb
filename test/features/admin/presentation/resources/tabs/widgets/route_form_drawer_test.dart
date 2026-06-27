import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/route_command_service.dart';
import 'package:veraprob/application/admin/route_command_service_provider.dart';
import 'package:veraprob/domain/entities/transit_route.dart';
import 'package:veraprob/features/admin/presentation/resources/tabs/widgets/route_form_drawer.dart';

class _ThrowingRouteService implements RouteCommandService {
  @override
  Future<TransitRoute> addRoute({
    required String shortName,
    required String longName,
    String? color,
  }) async => throw Exception('network error');

  @override
  Future<void> deleteRoute(String id) async {}
}

Widget _wrap({required Widget child, required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('RouteFormDrawer', () {
    testWidgets('shows generic error message on submit failure', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            routeCommandServiceProvider.overrideWithValue(
              _ThrowingRouteService(),
            ),
          ],
          child: RouteFormDrawer(onClose: () {}, onRouteAdded: (_) {}),
        ),
      );
      await tester.pump();

      // Fill required fields
      await tester.enterText(find.byType(TextFormField).at(0), 'L001');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Terminal Central → Zona Norte',
      );

      await tester.tap(find.text('Cadastrar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Não foi possível salvar a rota agora. Tente novamente.'),
        findsOneWidget,
      );
    });
  });
}
