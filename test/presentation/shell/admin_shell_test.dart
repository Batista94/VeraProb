import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/presentation/shell/admin_shell.dart';

void main() {
  group('AdminDestination enum', () {
    test('has exactly 6 destinations after hub consolidation', () {
      expect(AdminDestination.values.length, 6);
    });

    test('contains adminHub destination', () {
      final names = AdminDestination.values.map((d) => d.name).toList();
      expect(names, contains('adminHub'));
    });

    test('does not contain merged destinations', () {
      final names = AdminDestination.values.map((d) => d.name).toList();
      expect(names, isNot(contains('settings')));
      expect(names, isNot(contains('userManagement')));
      expect(names, isNot(contains('orgSettings')));
    });
  });
}
