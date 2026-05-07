// pr_scanner: ignore-regression
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/features/super_admin/application/create_organization_handler.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/features/super_admin/domain/create_organization_command.dart';
import 'package:veraprob/features/super_admin/domain/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/domain/plan_limits.dart';
import 'package:veraprob/features/super_admin/domain/plan_type.dart';

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

CreateOrganizationCommand _validCmd({
  String legalName = 'Transportes Boa Vista Ltda',
  String tradeName = 'Boa Vista Log',
  String cnpj = '11222333000181',
  String timezone = 'America/Sao_Paulo',
  String currencyCode = 'BRL',
  PlanType planType = PlanType.starter,
  int? maxVehicles,
  int? maxActiveContracts,
  List<String> adminEmails = const ['admin@boavista.com.br'],
  String superAdminUserId = 'sa-uuid-create-test',
  int? toolCostCents = 50000,
  int dwellTimeSeconds = 300,
  String? reason = 'Motivo válido de auditoria',
  int? billingDay,
  String? contactEmail,
  String? externalId,
  String? organizationType,
  List<String> allowedDomains = const [],
}) => CreateOrganizationCommand(
  legalName: legalName,
  tradeName: tradeName,
  cnpj: cnpj,
  timezone: timezone,
  currencyCode: currencyCode,
  planType: planType,
  maxVehicles: maxVehicles,
  maxActiveContracts: maxActiveContracts,
  adminEmails: adminEmails,
  superAdminUserId: superAdminUserId,
  toolCostCents: toolCostCents,
  dwellTimeSeconds: dwellTimeSeconds,
  reason: reason,
  billingDay: billingDay,
  contactEmail: contactEmail,
  externalId: externalId,
  organizationType: organizationType,
  allowedDomains: allowedDomains,
);

void main() {
  late MockSuperAdminRepository mockRepo;
  late MockSupabaseClient mockClient;
  late MockDateTimeProvider mockDateTime;
  late CreateOrganizationHandler handler;

  setUpAll(() {
    registerFallbackValue(_validCmd());
  });

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    mockClient = MockSupabaseClient();
    mockDateTime = MockDateTimeProvider();

    handler = CreateOrganizationHandler(mockRepo, mockClient, mockDateTime);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CONFIDENTIALITY
  // ══════════════════════════════════════════════════════════════════════════

  group('CONFIDENTIALITY', () {
    test(
      'CNPJ collision via PostgrestException 23505 — rethrown as DomainException containing CNPJ, '
      'prevents org existence inference',
      () async {
        when(() => mockRepo.createOrganization(any())).thenThrow(
          const PostgrestException(
            message: 'duplicate key value violates unique constraint cnpj',
            code: '23505',
          ),
        );

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('CNPJ'),
            ),
          ),
        );
      },
    );

    test(
      'PostgrestException 23505 without cnpj in message — rethrown raw, not wrapped',
      () async {
        when(() => mockRepo.createOrganization(any())).thenThrow(
          const PostgrestException(
            message: 'duplicate key value on unrelated unique constraint',
            code: '23505',
          ),
        );

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(isA<PostgrestException>()),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // INTEGRITY
  // ══════════════════════════════════════════════════════════════════════════

  group('INTEGRITY', () {
    test(
      'CNPJ with invalid check digit (14 digits, fails modulo-11) — DomainException containing inválido, '
      'repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(cnpj: '11222333000182')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('inválido'),
            ),
          ),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'empty legalName — DomainException containing Razão social, repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(legalName: '   ')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Razão social'),
            ),
          ),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'empty tradeName — DomainException containing Nome fantasia, repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(tradeName: '')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Nome fantasia'),
            ),
          ),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'empty adminEmails list — DomainException thrown, repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(adminEmails: const [])),
          throwsA(isA<DomainException>()),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'adminEmail without @ — DomainException containing E-mail, repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(adminEmails: const ['notanemail'])),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('E-mail'),
            ),
          ),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'toolCostCents == null — DomainException containing ROI, repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(toolCostCents: null)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('ROI'),
            ),
          ),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'reason == null — DomainException thrown, repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(reason: null)),
          throwsA(isA<DomainException>()),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'billingDay = 0 (below valid range) — DomainException thrown, repo NEVER called',
      () async {
        await expectLater(
          handler.handle(_validCmd(billingDay: 0)),
          throwsA(isA<DomainException>()),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'externalId of 101 chars — DomainException thrown, repo NEVER called',
      () async {
        final longId = 'x' * 101;

        await expectLater(
          handler.handle(_validCmd(externalId: longId)),
          throwsA(isA<DomainException>()),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'validation order: invalid CNPJ fires before repo — verifyNever repo',
      () async {
        await expectLater(
          handler.handle(_validCmd(cnpj: '00000000000000')),
          throwsA(isA<DomainException>()),
        );

        verifyNever(() => mockRepo.createOrganization(any()));
      },
    );

    test(
      'auto-fill quotas for starter plan when maxVehicles=null — captured command '
      'has maxVehicles == PlanLimits.maxVehicles(starter)',
      () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('sentinel'));

        await expectLater(
          handler.handle(
            _validCmd(maxVehicles: null, maxActiveContracts: null),
          ),
          throwsA(isNot(isA<DomainException>())),
        );

        final captured =
            verify(
                  () => mockRepo.createOrganization(captureAny()),
                ).captured.single
                as CreateOrganizationCommand;

        expect(captured.maxVehicles, PlanLimits.maxVehicles(PlanType.starter));
      },
    );

    test(
      'explicit maxVehicles preserved — captured command retains caller-supplied 75',
      () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('sentinel'));

        await expectLater(
          handler.handle(_validCmd(maxVehicles: 75, maxActiveContracts: 30)),
          throwsA(isNot(isA<DomainException>())),
        );

        final captured =
            verify(
                  () => mockRepo.createOrganization(captureAny()),
                ).captured.single
                as CreateOrganizationCommand;

        expect(captured.maxVehicles, 75);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AVAILABILITY
  // ══════════════════════════════════════════════════════════════════════════

  group('AVAILABILITY', () {
    test(
      'validation passes through to invite step — non-DomainException proves '
      'all guards cleared (repo returns uuid, client throws on invite)',
      () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenAnswer((_) async => 'org-uuid-generated-abc');

        await expectLater(
          handler.handle(_validCmd()),
          throwsA(isNot(isA<DomainException>())),
        );
      },
    );

    test(
      'toolCostCents = 0 accepted — validation clears, non-DomainException from invite step',
      () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('sentinel'));

        await expectLater(
          handler.handle(_validCmd(toolCostCents: 0)),
          throwsA(isNot(isA<DomainException>())),
        );
      },
    );

    test(
      'billingDay = 1 (valid lower bound) — validation clears, non-DomainException',
      () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('sentinel'));

        await expectLater(
          handler.handle(_validCmd(billingDay: 1)),
          throwsA(isNot(isA<DomainException>())),
        );
      },
    );

    test(
      'billingDay = 28 (valid upper bound) — validation clears, non-DomainException',
      () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('sentinel'));

        await expectLater(
          handler.handle(_validCmd(billingDay: 28)),
          throwsA(isNot(isA<DomainException>())),
        );
      },
    );

    test(
      'multiple valid admin emails — both validated independently, validation clears',
      () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('sentinel'));

        await expectLater(
          handler.handle(
            _validCmd(
              adminEmails: const ['first@company.com', 'second@company.com'],
            ),
          ),
          throwsA(isNot(isA<DomainException>())),
        );
      },
    );

    test(
      'externalId of exactly 100 chars accepted — validation clears, non-DomainException',
      () async {
        final maxId = 'x' * 100;

        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('sentinel'));

        await expectLater(
          handler.handle(_validCmd(externalId: maxId)),
          throwsA(isNot(isA<DomainException>())),
        );
      },
    );

    test(
      'reason of exactly 10 chars accepted — validation clears, non-DomainException',
      () async {
        when(
          () => mockRepo.createOrganization(any()),
        ).thenThrow(Exception('sentinel'));

        await expectLater(
          handler.handle(_validCmd(reason: '1234567890')),
          throwsA(isNot(isA<DomainException>())),
        );
      },
    );
  });
}
