import 'package:flutter_test/flutter_test.dart';

import 'package:pactaflow/application/intelligence/suggestion_engine.dart';
import 'package:pactaflow/domain/entities/operational_trip.dart';
import 'package:pactaflow/domain/entities/operational_warning.dart';
import 'package:pactaflow/domain/enums/trip_status.dart';

void main() {
  group('SuggestionEngine Rules', () {
    late SuggestionEngine engine;

    setUp(() {
      engine = SuggestionEngine();
    });

    test('Trip without attention required returns null suggestion', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        severityScore: 0,
        warnings: [],
        scheduledStart: DateTime.now(),
      );

      final suggestion = engine.generateSuggestion(trip: trip);

      expect(suggestion, isNull);
    });

    test('Returns Cancellation suggestion for stopped vehicle', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.interrupted,
        severityScore: 50,
        scheduledStart: DateTime.now(),
        warnings: [
          OperationalWarning(
            id: 'w1',
            type: 'vehicle_stopped',
            message: 'Stopped',
            severityScore: 50,
            detectedAt: DateTime.now(),
          ),
        ],
      );

      final suggestion = engine.generateSuggestion(trip: trip);

      expect(suggestion, isNotNull);
      expect(suggestion!.actionLabel, 'Cancelar Viagem');
      expect(suggestion.title, 'Veículo imobilizado na via');
    });

    test('Returns Interruption suggestion for critical delay', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        severityScore: 40,
        scheduledStart: DateTime.now(),
        warnings: [
          OperationalWarning(
            id: 'w1',
            type: 'delay_critical',
            message: 'Critical Delay',
            severityScore: 40,
            detectedAt: DateTime.now(),
          ),
        ],
      );

      final suggestion = engine.generateSuggestion(trip: trip);

      expect(suggestion, isNotNull);
      expect(suggestion!.actionLabel, 'Interromper');
      expect(suggestion.title, 'Atraso em cascata');
    });

    test('Returns Regularization suggestion for simple delay', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.delayed,
        severityScore: 20,
        warnings: [], // No critical warning, just delayed status
        scheduledStart: DateTime.now(),
      );

      final suggestion = engine.generateSuggestion(trip: trip);

      expect(suggestion, isNotNull);
      expect(suggestion!.actionLabel, 'Regularizar');
      expect(suggestion.title, 'Acompanhar evolução');
    });
  });
}
