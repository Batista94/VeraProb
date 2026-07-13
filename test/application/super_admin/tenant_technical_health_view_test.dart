import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/tenant_technical_health_view.dart';

void main() {
  group('ReplicationStatus', () {
    test('fromString returns correct enum for each valid value', () {
      expect(
        ReplicationStatus.fromString('healthy'),
        ReplicationStatus.healthy,
      );
      expect(
        ReplicationStatus.fromString('delayed'),
        ReplicationStatus.delayed,
      );
      expect(ReplicationStatus.fromString('failed'), ReplicationStatus.failed);
      expect(
        ReplicationStatus.fromString('unknown'),
        ReplicationStatus.unknown,
      );
    });

    test('fromString returns unknown for unrecognized values', () {
      expect(ReplicationStatus.fromString(''), ReplicationStatus.unknown);
      expect(
        ReplicationStatus.fromString('invalid'),
        ReplicationStatus.unknown,
      );
      expect(
        ReplicationStatus.fromString('HEALTHY'),
        ReplicationStatus.unknown,
      );
      expect(
        ReplicationStatus.fromString('something_else'),
        ReplicationStatus.unknown,
      );
    });

    test('toPulseStatus maps correctly', () {
      expect(ReplicationStatus.healthy.toPulseStatus(), PulseStatus.healthy);
      expect(ReplicationStatus.delayed.toPulseStatus(), PulseStatus.warning);
      expect(ReplicationStatus.failed.toPulseStatus(), PulseStatus.critical);
      expect(ReplicationStatus.unknown.toPulseStatus(), PulseStatus.critical);
    });
  });

  group('SchemaIntegrityStatus', () {
    test('fromString returns correct enum for each valid value', () {
      expect(
        SchemaIntegrityStatus.fromString('compliant'),
        SchemaIntegrityStatus.compliant,
      );
      expect(
        SchemaIntegrityStatus.fromString('minor_drift'),
        SchemaIntegrityStatus.minorDrift,
      );
      expect(
        SchemaIntegrityStatus.fromString('critical_drift'),
        SchemaIntegrityStatus.criticalDrift,
      );
    });

    test('fromString returns unknown for unrecognized values', () {
      expect(
        SchemaIntegrityStatus.fromString(''),
        SchemaIntegrityStatus.unknown,
      );
      expect(
        SchemaIntegrityStatus.fromString('invalid'),
        SchemaIntegrityStatus.unknown,
      );
      expect(
        SchemaIntegrityStatus.fromString('COMPLIANT'),
        SchemaIntegrityStatus.unknown,
      );
      expect(
        SchemaIntegrityStatus.fromString('minorDrift'),
        SchemaIntegrityStatus.unknown,
      );
    });

    test('toPulseStatus maps correctly', () {
      expect(
        SchemaIntegrityStatus.compliant.toPulseStatus(),
        PulseStatus.healthy,
      );
      expect(
        SchemaIntegrityStatus.minorDrift.toPulseStatus(),
        PulseStatus.warning,
      );
      expect(
        SchemaIntegrityStatus.criticalDrift.toPulseStatus(),
        PulseStatus.critical,
      );
      expect(
        SchemaIntegrityStatus.unknown.toPulseStatus(),
        PulseStatus.critical,
      );
    });
  });

  group('TenantTechnicalHealthView', () {
    test('fromJson parses valid data correctly', () {
      final json = <String, Object?>{
        'replication_status': 'healthy',
        'schema_integrity_status': 'minor_drift',
        'schema_version': 'v2024.06.15-r3',
        'last_check_at': '2024-06-15T10:30:00Z',
      };

      final view = TenantTechnicalHealthView.fromJson(json);

      expect(view.replicationStatus, ReplicationStatus.healthy);
      expect(view.schemaIntegrityStatus, SchemaIntegrityStatus.minorDrift);
      expect(view.schemaVersion, 'v2024.06.15-r3');
      expect(view.lastCheckAt, DateTime.utc(2024, 6, 15, 10, 30));
    });

    test('fromJson handles null fields with safe defaults', () {
      final json = <String, Object?>{
        'replication_status': null,
        'schema_integrity_status': null,
        'schema_version': null,
        'last_check_at': null,
      };

      final view = TenantTechnicalHealthView.fromJson(json);

      expect(view.replicationStatus, ReplicationStatus.unknown);
      expect(view.schemaIntegrityStatus, SchemaIntegrityStatus.unknown);
      expect(view.schemaVersion, 'unknown');
      expect(view.lastCheckAt, isNull);
    });

    test('fromJson handles missing fields with safe defaults', () {
      final json = <String, Object?>{};

      final view = TenantTechnicalHealthView.fromJson(json);

      expect(view.replicationStatus, ReplicationStatus.unknown);
      expect(view.schemaIntegrityStatus, SchemaIntegrityStatus.unknown);
      expect(view.schemaVersion, 'unknown');
      expect(view.lastCheckAt, isNull);
    });

    test('fromJson handles partial data', () {
      final json = <String, Object?>{
        'replication_status': 'delayed',
        'schema_version': 'v1.0.0',
      };

      final view = TenantTechnicalHealthView.fromJson(json);

      expect(view.replicationStatus, ReplicationStatus.delayed);
      expect(view.schemaIntegrityStatus, SchemaIntegrityStatus.unknown);
      expect(view.schemaVersion, 'v1.0.0');
      expect(view.lastCheckAt, isNull);
    });
  });
}
