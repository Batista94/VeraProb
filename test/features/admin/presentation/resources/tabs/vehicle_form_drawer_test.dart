import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/assets/i_vehicle_asset_repository.dart';
import 'package:veraprob/domain/entities/vehicle.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';
import 'package:veraprob/features/admin/presentation/resources/tabs/vehicle_form_drawer.dart';
import 'package:veraprob/state/providers/assets_providers.dart';

class _ThrowingVehicleRepo implements IVehicleAssetRepository {
  @override
  Future<Vehicle> addVehicle({
    required String plate,
    String? model,
    required int capacity,
    VehicleStatus status = VehicleStatus.available,
  }) async => throw Exception('network error');

  @override
  Future<List<Vehicle>> getVehicles() async => [];

  @override
  Future<Vehicle> updateVehicle(Vehicle vehicle) async => vehicle;

  @override
  Future<void> deleteVehicle(String vehicleId) async {}

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async => 0;
}

Widget _wrap({required Widget child, required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('VehicleFormDrawer', () {
    testWidgets('shows generic error message on submit failure', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            vehicleAssetRepositoryProvider.overrideWithValue(
              _ThrowingVehicleRepo(),
            ),
          ],
          child: VehicleFormDrawer(onClose: () {}, onVehicleAdded: (_) {}),
        ),
      );
      await tester.pump();

      // Fill plate (BR format) and capacity to pass validation
      await tester.enterText(find.byType(TextFormField).at(0), 'ABC-1234');
      await tester.enterText(find.byType(TextFormField).at(2), '48');

      await tester.tap(find.text('Cadastrar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Não foi possível salvar o veículo agora. Tente novamente.'),
        findsOneWidget,
      );
    });
  });
}
