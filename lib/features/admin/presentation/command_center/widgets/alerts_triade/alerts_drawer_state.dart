import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State to control the visibility of the Alerts Triade Drawer.
class _IsAlertsDrawerOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final isAlertsDrawerOpenProvider =
    NotifierProvider<_IsAlertsDrawerOpenNotifier, bool>(
      _IsAlertsDrawerOpenNotifier.new,
    );
