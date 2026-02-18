import 'package:flutter_riverpod/flutter_riverpod.dart';

// State provider for the currently selected admin tab index
final adminIndexProvider = StateProvider<int>((ref) => 0);
