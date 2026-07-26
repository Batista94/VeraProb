import 'package:test/test.dart';
import 'package:veraprob/domain/ad_hoc_cost/shadow_execution_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  group('ShadowExecutionStatus', () {
    test('dbValue maps enum to correct string representations', () {
      expect(ShadowExecutionStatus.unlinkedShadow.dbValue, 'UNLINKED_SHADOW');
      expect(ShadowExecutionStatus.reconciled.dbValue, 'RECONCILED');
      expect(
        ShadowExecutionStatus.reconciledAsNewRevenue.dbValue,
        'RECONCILED_AS_NEW_REVENUE',
      );
      expect(ShadowExecutionStatus.dismissed.dbValue, 'DISMISSED');
    });

    test('fromDb parses valid strings correctly', () {
      expect(
        ShadowExecutionStatusX.fromDb('UNLINKED_SHADOW'),
        ShadowExecutionStatus.unlinkedShadow,
      );
      expect(
        ShadowExecutionStatusX.fromDb('RECONCILED'),
        ShadowExecutionStatus.reconciled,
      );
      expect(
        ShadowExecutionStatusX.fromDb('RECONCILED_AS_NEW_REVENUE'),
        ShadowExecutionStatus.reconciledAsNewRevenue,
      );
      expect(
        ShadowExecutionStatusX.fromDb('DISMISSED'),
        ShadowExecutionStatus.dismissed,
      );
    });

    test(
      'fromDb throws IntegrityException on invalid inputs (Anti-Corruption)',
      () {
        expect(
          () => ShadowExecutionStatusX.fromDb('UNKNOWN_STATE'),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Unknown ShadowExecutionStatus: UNKNOWN_STATE'),
            ),
          ),
        );

        expect(
          () => ShadowExecutionStatusX.fromDb(
            'unlinked_shadow',
          ), // Case-sensitive check
          throwsA(isA<IntegrityException>()),
        );
      },
    );
  });
}
