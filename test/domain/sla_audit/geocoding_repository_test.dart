import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/geocoding_repository.dart';

void main() {
  group('PlaceSuggestion', () {
    test('happy path: constructs successfully with valid coordinates', () {
      const suggestion = PlaceSuggestion(
        displayName: 'Av. Paulista, São Paulo',
        lat: -23.5613,
        lng: -46.6565,
      );

      expect(suggestion.displayName, equals('Av. Paulista, São Paulo'));
      expect(suggestion.lat, equals(-23.5613));
      expect(suggestion.lng, equals(-46.6565));
    });

    test('const instantiation is supported', () {
      const suggestion = PlaceSuggestion(
        displayName: 'Origin',
        lat: 0.0,
        lng: 0.0,
      );

      expect(suggestion, isNotNull);
    });

    group('Integrity constraints (assertions)', () {
      test('throws AssertionError when latitude is out of bounds', () {
        expect(
          () => PlaceSuggestion(
            displayName: 'Invalid Lat Upper',
            lat: 90.1,
            lng: 0.0,
          ),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.message,
              'message',
              contains('Latitude must be between -90 and 90'),
            ),
          ),
        );

        expect(
          () => PlaceSuggestion(
            displayName: 'Invalid Lat Lower',
            lat: -90.1,
            lng: 0.0,
          ),
          throwsA(isA<AssertionError>()),
        );
      });

      test('throws AssertionError when longitude is out of bounds', () {
        expect(
          () => PlaceSuggestion(
            displayName: 'Invalid Lng Upper',
            lat: 0.0,
            lng: 180.1,
          ),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.message,
              'message',
              contains('Longitude must be between -180 and 180'),
            ),
          ),
        );

        expect(
          () => PlaceSuggestion(
            displayName: 'Invalid Lng Lower',
            lat: 0.0,
            lng: -180.1,
          ),
          throwsA(isA<AssertionError>()),
        );
      });
    });
  });
}
