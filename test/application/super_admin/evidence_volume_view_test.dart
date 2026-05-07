import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/application/evidence_volume_view.dart';

void main() {
  group('EvidenceVolumeView', () {
    test('can be constructed with const constructor', () {
      const view = EvidenceVolumeView(
        totalHistorical: 15000,
        totalMonthly: 320,
      );
      expect(view.totalHistorical, 15000);
      expect(view.totalMonthly, 320);
    });

    test('fromJson parses valid data correctly', () {
      final json = <String, Object?>{
        'total_historical': 25000,
        'total_monthly': 1200,
      };

      final view = EvidenceVolumeView.fromJson(json);

      expect(view.totalHistorical, 25000);
      expect(view.totalMonthly, 1200);
    });

    test('fromJson handles null fields with fallback to 0', () {
      final json = <String, Object?>{
        'total_historical': null,
        'total_monthly': null,
      };

      final view = EvidenceVolumeView.fromJson(json);

      expect(view.totalHistorical, 0);
      expect(view.totalMonthly, 0);
    });

    test('fromJson handles missing fields with fallback to 0', () {
      final json = <String, Object?>{};

      final view = EvidenceVolumeView.fromJson(json);

      expect(view.totalHistorical, 0);
      expect(view.totalMonthly, 0);
    });

    test('fromJson handles double values via num cast', () {
      final json = <String, Object?>{
        'total_historical': 5000.0,
        'total_monthly': 150.7,
      };

      final view = EvidenceVolumeView.fromJson(json);

      expect(view.totalHistorical, 5000);
      expect(view.totalMonthly, 150);
    });

    test('fromJson handles partial data', () {
      final json = <String, Object?>{'total_historical': 9999};

      final view = EvidenceVolumeView.fromJson(json);

      expect(view.totalHistorical, 9999);
      expect(view.totalMonthly, 0);
    });
  });
}
