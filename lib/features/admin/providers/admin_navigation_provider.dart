import 'package:flutter_riverpod/flutter_riverpod.dart';

// State provider for the currently selected admin tab index
class _AdminIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

final adminIndexProvider = NotifierProvider<_AdminIndexNotifier, int>(
  _AdminIndexNotifier.new,
);
