import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesNotifier extends StateNotifier<List<String>> {
  static const _key = 'favorite_routes';
  final SharedPreferences _prefs;

  FavoritesNotifier(this._prefs) : super([]) {
    _loadFavorites();
  }

  void _loadFavorites() {
    final favorites = _prefs.getStringList(_key) ?? [];
    state = favorites;
  }

  Future<void> toggleFavorite(String routeId) async {
    final List<String> current = List.from(state);
    if (current.contains(routeId)) {
      current.remove(routeId);
    } else {
      current.add(routeId);
    }
    state = current;
    await _prefs.setStringList(_key, current);
  }

  bool isFavorite(String routeId) => state.contains(routeId);
}
