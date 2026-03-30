import 'package:postgres/postgres.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('INV-1: RLS Sovereignty Breach (Red Team Simulation)', () {
    late Connection conn;

    setUpAll(() async {
      // Trying password from .env: 'veraprob123!'
      conn = await Connection.open(
        Endpoint(
          host: '127.0.0.1',
          port: 54322,
          database: 'postgres',
          username: 'postgres',
          password: 'veraprob123!',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
    });

    tearDownAll(() async {
      await conn.close();
    });

    test('Organization Alpha CANNOT see or modify Organization Beta data', () async {
      const uuid = Uuid();
      final orgA = uuid.v4();
      final orgB = uuid.v4();

      // 1. Setup Organizations (Service Role context)
      await conn.execute(
        "INSERT INTO organizations (id, name, legal_name, is_active) VALUES ('$orgA', 'Alpha Corp', 'Alpha Legal', true)",
      );
      await conn.execute(
        "INSERT INTO organizations (id, name, legal_name, is_active) VALUES ('$orgB', 'Beta Corp', 'Beta Legal', true)",
      );

      // 2. Insert test data for both
      await conn.execute("""
        INSERT INTO sla_audit_ledger_v2 (organization_id, timestamp, action_type, entity_id, operator_id) 
        VALUES ('$orgA', NOW(), 'TEST_ACTION', 'entity-a', 'user-a')
      """);
      await conn.execute("""
        INSERT INTO sla_audit_ledger_v2 (organization_id, timestamp, action_type, entity_id, operator_id) 
        VALUES ('$orgB', NOW(), 'TEST_ACTION', 'entity-b', 'user-b')
      """);

      // 3. Switch to Org Alpha Context (Simulate JWT claims)
      await conn.run((tx) async {
        await tx.execute(
          "SET LOCAL request.jwt.claims = '{\"app_metadata\": {\"org_id\": \"$orgA\"}}'",
        );

        // 4. BREACH ATTEMPT: Try to read Beta's ledger
        final results = await tx.execute("SELECT * FROM sla_audit_ledger_v2");

        // Verify isolation: Should only see 1 row (Org Alpha)
        expect(
          results.length,
          1,
          reason: 'RLS should filter out Org Beta data',
        );
        expect(
          results.first.toColumnMap()['organization_id'].toString(),
          orgA,
          reason: 'Returned row must belong to Org Alpha',
        );

        // 5. BREACH ATTEMPT: Try to insert data for Beta from Alpha's context
        try {
          await tx.execute("""
            INSERT INTO sla_audit_ledger_v2 (organization_id, timestamp, action_type, entity_id, operator_id) 
            VALUES ('$orgB', NOW(), 'DATA_BREACH', 'entity-b', 'user-a')
          """);
          fail('RLS should have rejected cross-tenant insertion');
        } catch (e) {
          expect(
            e.toString(),
            contains('violates row-level security policy'),
            reason: 'Database must throw RLS violation exception',
          );
        }
      });
    });
  });
}
