import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:busflow/features/shared/data/repositories/favorites_repository.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late MockSharedPreferences mockPrefs;
  late FavoritesNotifier notifier;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    // Default return for getStringList
    when(() => mockPrefs.getStringList(any())).thenReturn([]);
    // Mock setStringList to return true
    when(
      () => mockPrefs.setStringList(any(), any()),
    ).thenAnswer((_) async => true);

    notifier = FavoritesNotifier(mockPrefs);
  });

  group('FavoritesNotifier', () {
    test('initial state should be empty', () {
      expect(notifier.state, isEmpty);
    });

    test('toggleFavorite should add item if not present', () async {
      await notifier.toggleFavorite('TripA');
      expect(notifier.state, contains('TripA'));
      verify(
        () => mockPrefs.setStringList('favorite_routes', ['TripA']),
      ).called(1);
    });

    test('toggleFavorite should remove item if present', () async {
      // Setup initial state manually or via toggle
      await notifier.toggleFavorite('TripA');
      expect(notifier.state, contains('TripA'));

      await notifier.toggleFavorite('TripA');
      expect(notifier.state, isEmpty);
      verify(() => mockPrefs.setStringList('favorite_routes', [])).called(1);
    });

    test('isFavorite should return correct bool', () async {
      await notifier.toggleFavorite('TripB');
      expect(notifier.isFavorite('TripB'), true);
      expect(notifier.isFavorite('TripZ'), false);
    });
  });
}
