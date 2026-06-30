import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/shared/domain_error_text.dart';
import 'package:veraprob/domain/shared/authorization_exception.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/shared/concurrent_modification_exception.dart';
import 'package:veraprob/domain/sla_audit/dual_control_self_approval_exception.dart';

void main() {
  group('humanizeDomainError', () {
    test('should extract message from ConflictException', () {
      const error = ConflictException(
        resourceType: 'driver',
        resourceId: '123',
        clientVersion: 1,
      );
      expect(
        humanizeDomainError(error),
        'Optimistic lock conflict on driver "123": client sent version 1, resource no longer exists',
      );
    });

    test('should extract message from IntegrityException', () {
      const error = IntegrityException('Violação de integridade.');
      expect(humanizeDomainError(error), 'Violação de integridade.');
    });

    test('should extract message from AuthorizationException', () {
      const error = AuthorizationException('Acesso negado.');
      expect(humanizeDomainError(error), 'Acesso negado.');
    });

    test('should extract message from SovereigntyViolationException', () {
      const error = SovereigntyViolationException(
        payloadOrgId: 'org1',
        jwtOrgId: 'org2',
        message: 'Violação de organização.',
      );
      expect(humanizeDomainError(error), 'Violação de organização.');
    });

    test('should extract message from ResourceNotFoundException', () {
      const error = ResourceNotFoundException(
        message: 'Recurso não encontrado.',
      );
      expect(humanizeDomainError(error), 'Recurso não encontrado.');
    });

    test('should extract message from ConcurrentModificationException', () {
      const error = ConcurrentModificationException(
        idempotencyKey: 'key1',
        commandPath: 'path/cmd',
        message: 'Modificação concorrente.',
      );
      expect(humanizeDomainError(error), 'Modificação concorrente.');
    });

    test('should extract message from IdempotencyProcessingException', () {
      const error = IdempotencyProcessingException(
        idempotencyKey: 'key2',
        commandPath: 'path/cmd2',
        message: 'Falha de idempotência.',
      );
      expect(humanizeDomainError(error), 'Falha de idempotência.');
    });

    test('should extract message from DualControlSelfApprovalException', () {
      const error = DualControlSelfApprovalException(
        message: 'Auto-aprovação negada.',
        queueEntryId: 'mock-id',
      );
      expect(humanizeDomainError(error), 'Auto-aprovação negada.');
    });

    test('should fallback to safe string for unknown errors', () {
      expect(
        humanizeDomainError(Exception('Some infra error')),
        'Erro Desconhecido: Exception: Some infra error',
      );
    });

    test('should fallback to safe string for null', () {
      expect(humanizeDomainError(null), 'Erro Desconhecido: null');
    });
  });
}
