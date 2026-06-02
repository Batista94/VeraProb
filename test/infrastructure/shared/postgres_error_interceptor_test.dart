import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// INV-26: Error Parity — Postgres-specific error codes MUST NOT leak
/// to the client. All information-disclosure errors are mapped to canonical
/// 404 responses via ResourceNotFoundException.
class TestClass with PostgresErrorInterceptor {}

void main() {
  late TestClass testClass;

  setUp(() {
    testClass = TestClass();
  });

  group('PostgresErrorInterceptor.mapPostgrestException', () {
    test(
      'maps 22P02 (invalid_text_representation) to ResourceNotFoundException',
      () {
        const exception = PostgrestException(
          message: 'invalid input syntax for type uuid: "not-a-uuid"',
          code: '22P02',
        );

        final result = testClass.mapPostgrestToDomainException(
          exception,
          resourceType: 'contract',
          resourceId: 'not-a-uuid',
        );

        expect(result, isA<ResourceNotFoundException>());
        final rnf = result as ResourceNotFoundException;
        expect(rnf.resourceType, 'contract');
        expect(rnf.resourceId, 'not-a-uuid');
      },
    );

    test(
      'maps nested JSON 22P02 in message with HTTP code 400 to ResourceNotFoundException',
      () {
        const exception = PostgrestException(
          message:
              '{"code":"22P02","details":null,"hint":null,"message":"invalid input syntax for type uuid: \\"non-existent-ledger-id\\""}',
          code: '400',
        );

        final result = testClass.mapPostgrestToDomainException(
          exception,
          resourceType: 'forensic_evidence_snapshot',
          resourceId: 'non-existent-ledger-id',
        );

        expect(result, isA<ResourceNotFoundException>());
        final rnf = result as ResourceNotFoundException;
        expect(rnf.resourceType, 'forensic_evidence_snapshot');
        expect(rnf.resourceId, 'non-existent-ledger-id');
      },
    );

    test('maps PGRST116 (not_found) to ResourceNotFoundException', () {
      const exception = PostgrestException(
        message: 'The result contains 0 rows',
        code: 'PGRST116',
      );

      final result = testClass.mapPostgrestToDomainException(
        exception,
        resourceType: 'sla_template',
      );

      expect(result, isA<ResourceNotFoundException>());
      final rnf = result as ResourceNotFoundException;
      expect(rnf.resourceType, 'sla_template');
    });

    test(
      'maps P0001 (RAISE EXCEPTION) to DomainException with original message',
      () {
        const exception = PostgrestException(
          message: 'Contract already exists for this organization',
          code: 'P0001',
        );

        final result = testClass.mapPostgrestToDomainException(exception);

        expect(result, isA<IntegrityException>());
        final de = result as IntegrityException;
        expect(de.message, 'Contract already exists for this organization');
      },
    );

    test('maps 23505 (unique_violation) to IntegrityException', () {
      const exception = PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
        details: 'Key (cnpj)=(12.345.678/0001-90) already exists.',
      );

      final result = testClass.mapPostgrestToDomainException(
        exception,
        resourceType: 'organization',
      );

      expect(result, isA<IntegrityException>());
    });

    test('maps 23502 (not_null_violation) to a clear IntegrityException', () {
      const exception = PostgrestException(
        message:
            'null value in column "name" of relation "contractors" '
            'violates not-null constraint',
        code: '23502',
      );

      final result = testClass.mapPostgrestToDomainException(
        exception,
        resourceType: 'contractor',
      );

      expect(result, isA<IntegrityException>());
      final de = result as IntegrityException;
      // Raw DB column text must NOT leak; a domain-language message is shown.
      expect(de.message, contains('Campo obrigatório'));
      expect(de.message, isNot(contains('not-null')));
    });

    test('rethrows unhandled error codes (fail-fast)', () {
      const exception = PostgrestException(
        message: 'Some unknown PostgREST error',
        code: 'UNKNOWN_CODE',
      );

      expect(
        () => testClass.mapPostgrestToDomainException(exception),
        throwsA(same(exception)),
      );
    });

    test(
      'passes through resourceType and resourceId to ResourceNotFoundException',
      () {
        const exception = PostgrestException(
          message: 'not found',
          code: 'PGRST116',
        );

        final result =
            testClass.mapPostgrestToDomainException(
                  exception,
                  resourceType: 'vehicle',
                  resourceId: 'abc-123',
                )
                as ResourceNotFoundException;

        expect(result.resourceType, 'vehicle');
        expect(result.resourceId, 'abc-123');
      },
    );

    test('passes through message to IntegrityException for P0001', () {
      const customMsg = 'Quota exceeded for this organization';
      const exception = PostgrestException(message: customMsg, code: 'P0001');

      final result =
          testClass.mapPostgrestToDomainException(exception)
              as IntegrityException;

      expect(result.message, customMsg);
    });

    test('handles 22P02 without optional resource params', () {
      const exception = PostgrestException(
        message: 'invalid UUID',
        code: '22P02',
      );

      final result = testClass.mapPostgrestToDomainException(exception);

      expect(result, isA<ResourceNotFoundException>());
    });

    test('maps PGRST204 (column_not_found) to ResourceNotFoundException', () {
      const exception = PostgrestException(
        message: 'column "org_id" not found',
        code: 'PGRST204',
      );

      final result = testClass.mapPostgrestToDomainException(exception);

      expect(result, isA<ResourceNotFoundException>());
    });

    test('maps 23503 (foreign_key_violation) to ResourceNotFoundException '
        '(INV-26: no schema leak)', () {
      const exception = PostgrestException(
        message:
            'insert or update on table "execution_states" violates '
            'foreign key constraint "execution_states_contract_id_fkey"',
        code: '23503',
        details:
            'Key (contract_id)=(contract-fake-uuid) is not present '
            'in table "contracts".',
      );

      final result = testClass.mapPostgrestToDomainException(
        exception,
        resourceType: 'execution_state',
        resourceId: 'state-123',
      );

      expect(result, isA<ResourceNotFoundException>());
      final rnf = result as ResourceNotFoundException;
      expect(rnf.resourceType, 'execution_state');
      expect(rnf.resourceId, 'state-123');
      // No table names, FK names, or column names leak to the exception
      expect(rnf.message, 'Resource not found.');
    });
  });
}
