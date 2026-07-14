import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/admin/update_org_operational_params_command.dart';
import 'package:veraprob/application/admin/update_org_operational_params_handler.dart';
import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

class MockOrganizationRepository extends Mock
    implements OrganizationRepository {}

class MockSystemAuditLogService extends Mock implements SystemAuditLogService {}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _orgId = 'org-uuid-test-001';
const _sessionId = 'session-uuid-test-001';
const _validReason = 'Ajuste operacional conforme nova política de segurança';

Organization _buildOrg({
  String id = _orgId,
  int dwellTimeSeconds = 300,
  double? maxKinematicSpeedKmh = 80.0,
}) => Organization(
  id: id,
  name: 'Transportadora Teste',
  timezone: 'America/Sao_Paulo',
  currencyCode: 'BRL',
  status: OrgStatus.active,
  createdAt: DateTime(2024, 1, 1),
  dwellTimeSeconds: dwellTimeSeconds,
  capabilities: OrgCapabilities(maxKinematicSpeedKmh: maxKinematicSpeedKmh),
);

UpdateOrgOperationalParamsCommand _cmd({
  String organizationId = _orgId,
  UserRole callerRole = UserRole.admin,
  int? dwellTimeSeconds,
  double? maxKinematicSpeedKmh,
  String reason = _validReason,
  String sessionId = _sessionId,
}) => UpdateOrgOperationalParamsCommand(
  organizationId: organizationId,
  callerRole: callerRole,
  dwellTimeSeconds: dwellTimeSeconds,
  maxKinematicSpeedKmh: maxKinematicSpeedKmh,
  reason: reason,
  sessionId: sessionId,
);

void main() {
  late MockTenantValidationService mockTenantValidator;
  late MockOrganizationRepository mockRepository;
  late MockSystemAuditLogService mockAuditLogService;
  late UpdateOrgOperationalParamsHandler handler;
  late UpdateOrgOperationalParamsHandler handlerWithoutAudit;

  setUpAll(() {
    registerFallbackValue(_buildOrg());
  });

  setUp(() {
    mockTenantValidator = MockTenantValidationService();
    mockRepository = MockOrganizationRepository();
    mockAuditLogService = MockSystemAuditLogService();

    handler = UpdateOrgOperationalParamsHandler(
      tenantValidator: mockTenantValidator,
      repository: mockRepository,
      auditLogService: mockAuditLogService,
    );

    handlerWithoutAudit = UpdateOrgOperationalParamsHandler(
      tenantValidator: mockTenantValidator,
      repository: mockRepository,
      auditLogService: null,
    );

    // Default stubs
    when(
      () => mockTenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockRepository.findById(any()),
    ).thenAnswer((_) async => _buildOrg());

    when(() => mockRepository.update(any())).thenAnswer((_) async {});

    when(
      () => mockAuditLogService.logGovernanceChange(
        eventType: any(named: 'eventType'),
        reason: any(named: 'reason'),
        actorType: any(named: 'actorType'),
        organizationId: any(named: 'organizationId'),
        organizationName: any(named: 'organizationName'),
        oldSnapshot: any(named: 'oldSnapshot'),
        newSnapshot: any(named: 'newSnapshot'),
      ),
    ).thenAnswer((_) async {});
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. PHYSICAL LIMIT VIOLATION (INV-10)
  // ═══════════════════════════════════════════════════════════════════════════

  group('INV-10: Physical Limit Violation — maxKinematicSpeedKmh', () {
    test('speed = 0 → throws DomainException (must be > 0)', () async {
      await expectLater(
        handler.handle(_cmd(maxKinematicSpeedKmh: 0.0)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('maior que zero'),
          ),
        ),
      );
      verifyNever(() => mockRepository.update(any()));
    });

    test('speed = -10.0 → throws DomainException (negative)', () async {
      await expectLater(
        handler.handle(_cmd(maxKinematicSpeedKmh: -10.0)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('maior que zero'),
          ),
        ),
      );
      verifyNever(() => mockRepository.update(any()));
    });

    test('speed = 201.0 → throws DomainException (exceeds 200 km/h)', () async {
      await expectLater(
        handler.handle(_cmd(maxKinematicSpeedKmh: 201.0)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('200 km/h'),
          ),
        ),
      );
      verifyNever(() => mockRepository.update(any()));
    });

    test('speed = 200.0 → accepted (boundary value)', () async {
      await handler.handle(_cmd(maxKinematicSpeedKmh: 200.0));
      verify(() => mockRepository.update(any())).called(1);
    });

    test('speed = 0.01 → accepted (minimum positive value)', () async {
      await handler.handle(_cmd(maxKinematicSpeedKmh: 0.01));
      verify(() => mockRepository.update(any())).called(1);
    });

    test('speed = 500.0 → throws DomainException (extreme value)', () async {
      await expectLater(
        handler.handle(_cmd(maxKinematicSpeedKmh: 500.0)),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('INV-10: Physical Limit Violation — dwellTimeSeconds', () {
    test(
      'dwellTime = 59 → throws DomainException (below 60s minimum)',
      () async {
        await expectLater(
          handler.handle(_cmd(dwellTimeSeconds: 59)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('60 segundos'),
            ),
          ),
        );
        verifyNever(() => mockRepository.update(any()));
      },
    );

    test(
      'dwellTime = 1801 → throws DomainException (above 1800s maximum)',
      () async {
        await expectLater(
          handler.handle(_cmd(dwellTimeSeconds: 1801)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('1800 segundos'),
            ),
          ),
        );
        verifyNever(() => mockRepository.update(any()));
      },
    );

    test('dwellTime = 0 → throws DomainException (zero)', () async {
      await expectLater(
        handler.handle(_cmd(dwellTimeSeconds: 0)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('60 segundos'),
          ),
        ),
      );
    });

    test('dwellTime = -1 → throws DomainException (negative)', () async {
      await expectLater(
        handler.handle(_cmd(dwellTimeSeconds: -1)),
        throwsA(isA<DomainException>()),
      );
    });

    test('dwellTime = 60 → accepted (boundary minimum)', () async {
      await handler.handle(_cmd(dwellTimeSeconds: 60));
      verify(() => mockRepository.update(any())).called(1);
    });

    test('dwellTime = 1800 → accepted (boundary maximum)', () async {
      await handler.handle(_cmd(dwellTimeSeconds: 1800));
      verify(() => mockRepository.update(any())).called(1);
    });

    test('error messages are clear and specify limits', () async {
      try {
        await handler.handle(_cmd(dwellTimeSeconds: 59));
        fail('Should have thrown');
      } on DomainException catch (e) {
        expect(e.message, contains('mínimo'));
        expect(e.message, contains('60'));
      }

      try {
        await handler.handle(_cmd(dwellTimeSeconds: 1801));
        fail('Should have thrown');
      } on DomainException catch (e) {
        expect(e.message, contains('máximo'));
        expect(e.message, contains('1800'));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. AUDIT LOG CONSISTENCY (Snapshot Attack)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Audit Log Consistency — Snapshot Attack Prevention', () {
    test('oldSnapshot contains REAL org data before mutation', () async {
      final existingOrg = _buildOrg(
        dwellTimeSeconds: 420,
        maxKinematicSpeedKmh: 90.0,
      );
      when(
        () => mockRepository.findById(_orgId),
      ).thenAnswer((_) async => existingOrg);

      await handler.handle(
        _cmd(dwellTimeSeconds: 600, maxKinematicSpeedKmh: 120.0),
      );

      final captured = verify(
        () => mockAuditLogService.logGovernanceChange(
          eventType: any(named: 'eventType'),
          reason: any(named: 'reason'),
          actorType: any(named: 'actorType'),
          organizationId: any(named: 'organizationId'),
          organizationName: any(named: 'organizationName'),
          oldSnapshot: captureAny(named: 'oldSnapshot'),
          newSnapshot: any(named: 'newSnapshot'),
        ),
      ).captured;

      final oldSnapshot = captured.first as Map<String, Object?>;
      expect(oldSnapshot['dwell_time_seconds'], equals(420));
      expect(oldSnapshot['max_kinematic_speed_kmh'], equals(90.0));
    });

    test('newSnapshot contains exactly what was sent in the command', () async {
      await handler.handle(
        _cmd(dwellTimeSeconds: 900, maxKinematicSpeedKmh: 150.0),
      );

      final captured = verify(
        () => mockAuditLogService.logGovernanceChange(
          eventType: any(named: 'eventType'),
          reason: any(named: 'reason'),
          actorType: any(named: 'actorType'),
          organizationId: any(named: 'organizationId'),
          organizationName: any(named: 'organizationName'),
          oldSnapshot: any(named: 'oldSnapshot'),
          newSnapshot: captureAny(named: 'newSnapshot'),
        ),
      ).captured;

      final newSnapshot = captured.first as Map<String, Object?>;
      expect(newSnapshot['dwell_time_seconds'], equals(900));
      expect(newSnapshot['max_kinematic_speed_kmh'], equals(150.0));
    });

    test(
      'newSnapshot with null fields reflects partial update intent',
      () async {
        await handler.handle(
          _cmd(dwellTimeSeconds: 600, maxKinematicSpeedKmh: null),
        );

        final captured = verify(
          () => mockAuditLogService.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            organizationId: any(named: 'organizationId'),
            organizationName: any(named: 'organizationName'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: captureAny(named: 'newSnapshot'),
          ),
        ).captured;

        final newSnapshot = captured.first as Map<String, Object?>;
        expect(newSnapshot['dwell_time_seconds'], equals(600));
        expect(newSnapshot['max_kinematic_speed_kmh'], isNull);
      },
    );

    test('auditLogService null → handler continues without logging', () async {
      await handlerWithoutAudit.handle(_cmd(dwellTimeSeconds: 120));

      verify(() => mockRepository.update(any())).called(1);
      verifyNever(
        () => mockAuditLogService.logGovernanceChange(
          eventType: any(named: 'eventType'),
          reason: any(named: 'reason'),
          actorType: any(named: 'actorType'),
          organizationId: any(named: 'organizationId'),
          organizationName: any(named: 'organizationName'),
          oldSnapshot: any(named: 'oldSnapshot'),
          newSnapshot: any(named: 'newSnapshot'),
        ),
      );
    });

    test('audit log receives correct eventType and actorType', () async {
      await handler.handle(_cmd(dwellTimeSeconds: 120));

      verify(
        () => mockAuditLogService.logGovernanceChange(
          eventType: 'OPERATIONAL_PARAM_CHANGE',
          reason: _validReason,
          actorType: ActorType.human,
          organizationId: _orgId,
          organizationName: 'Transportadora Teste',
          oldSnapshot: any(named: 'oldSnapshot'),
          newSnapshot: any(named: 'newSnapshot'),
        ),
      ).called(1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. RBAC UNAUTHORIZED ACCESS
  // ═══════════════════════════════════════════════════════════════════════════

  group('RBAC — Unauthorized Access', () {
    test('operator role → throws Unauthorized DomainException', () async {
      await expectLater(
        handler.handle(_cmd(callerRole: UserRole.operator)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Unauthorized'), contains('cannot modify')),
          ),
        ),
      );
      verifyNever(() => mockRepository.findById(any()));
      verifyNever(() => mockRepository.update(any()));
    });

    test('auditor role → throws Unauthorized DomainException', () async {
      await expectLater(
        handler.handle(_cmd(callerRole: UserRole.auditor)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Unauthorized'), contains('cannot modify')),
          ),
        ),
      );
    });

    test(
      'contractorViewer role → throws Unauthorized DomainException',
      () async {
        await expectLater(
          handler.handle(_cmd(callerRole: UserRole.contractorViewer)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Unauthorized'),
            ),
          ),
        );
      },
    );

    test('error message includes the offending role name', () async {
      try {
        await handler.handle(_cmd(callerRole: UserRole.operator));
        fail('Should have thrown');
      } on DomainException catch (e) {
        expect(e.message, contains('UserRole.operator'));
      }
    });

    test('admin role → allowed (no RBAC exception)', () async {
      await handler.handle(
        _cmd(callerRole: UserRole.admin, dwellTimeSeconds: 120),
      );
      verify(() => mockRepository.update(any())).called(1);
    });

    test('superAdmin role → allowed (no RBAC exception)', () async {
      await handler.handle(
        _cmd(callerRole: UserRole.superAdmin, dwellTimeSeconds: 120),
      );
      verify(() => mockRepository.update(any())).called(1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. JUSTIFICATION INTEGRITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('Justification Integrity', () {
    test('empty reason → throws DomainException', () async {
      await expectLater(
        handler.handle(_cmd(reason: '')),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('obrigatória'),
          ),
        ),
      );
      verifyNever(() => mockRepository.findById(any()));
    });

    test('whitespace-only reason → throws DomainException', () async {
      await expectLater(
        handler.handle(_cmd(reason: '         ')),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('obrigatória'),
          ),
        ),
      );
    });

    test('reason with 9 chars → throws DomainException (< 10)', () async {
      await expectLater(
        handler.handle(_cmd(reason: '123456789')),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('10 caracteres'),
          ),
        ),
      );
    });

    test(
      'reason with 9 chars + leading spaces → throws (trimmed < 10)',
      () async {
        await expectLater(
          handler.handle(_cmd(reason: '   12345  ')),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('10 caracteres'),
            ),
          ),
        );
      },
    );

    test('reason with exactly 10 chars → accepted', () async {
      await handler.handle(_cmd(reason: '1234567890', dwellTimeSeconds: 120));
      verify(() => mockRepository.update(any())).called(1);
    });

    test(
      'reason with tabs and newlines only → throws (empty after trim)',
      () async {
        await expectLater(
          handler.handle(_cmd(reason: '\t\n\r  \t')),
          throwsA(isA<DomainException>()),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. RACE CONDITION — Org Not Found
  // ═══════════════════════════════════════════════════════════════════════════

  group(
    'Race Condition — Organization deleted between validation and fetch',
    () {
      test(
        'findById returns null → throws DomainException with org ID',
        () async {
          when(
            () => mockRepository.findById(_orgId),
          ).thenAnswer((_) async => null);

          await expectLater(
            handler.handle(_cmd(dwellTimeSeconds: 120)),
            throwsA(
              isA<DomainException>().having(
                (e) => e.message,
                'message',
                contains('Organização não encontrada.'),
              ),
            ),
          );
          verifyNever(() => mockRepository.update(any()));
        },
      );

      test('org deleted mid-flight → no audit log written', () async {
        when(
          () => mockRepository.findById(_orgId),
        ).thenAnswer((_) async => null);

        try {
          await handler.handle(_cmd(dwellTimeSeconds: 120));
        } on DomainException {
          // expected
        }

        verifyNever(
          () => mockAuditLogService.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            organizationId: any(named: 'organizationId'),
            organizationName: any(named: 'organizationName'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
          ),
        );
      });

      test(
        'tenant validation passes but org vanishes → correct error flow',
        () async {
          // Tenant validation succeeds (session is valid)
          when(
            () => mockTenantValidator.assertTenantMatches(
              payloadOrgId: _orgId,
              sessionId: _sessionId,
            ),
          ).thenAnswer((_) async {});

          // But org is gone by the time we fetch
          when(
            () => mockRepository.findById(_orgId),
          ).thenAnswer((_) async => null);

          await expectLater(
            handler.handle(_cmd(dwellTimeSeconds: 120)),
            throwsA(isA<DomainException>()),
          );

          // Verify tenant validation was called (proving the race window)
          verify(
            () => mockTenantValidator.assertTenantMatches(
              payloadOrgId: _orgId,
              sessionId: _sessionId,
            ),
          ).called(1);
        },
      );
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. PARTIAL UPDATE INTEGRITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('Partial Update Integrity — copyWith preservation', () {
    test(
      'updating only speed → dwellTimeSeconds preserved in persisted entity',
      () async {
        final existingOrg = _buildOrg(
          dwellTimeSeconds: 420,
          maxKinematicSpeedKmh: 80.0,
        );
        when(
          () => mockRepository.findById(_orgId),
        ).thenAnswer((_) async => existingOrg);

        await handler.handle(
          _cmd(maxKinematicSpeedKmh: 150.0, dwellTimeSeconds: null),
        );

        final captured =
            verify(() => mockRepository.update(captureAny())).captured.first
                as Organization;

        // dwellTimeSeconds must remain at original value (420)
        expect(captured.dwellTimeSeconds, equals(420));
        // speed must be updated
        expect(captured.capabilities.maxKinematicSpeedKmh, equals(150.0));
      },
    );

    test(
      'updating only dwellTime → maxKinematicSpeedKmh preserved in persisted entity',
      () async {
        final existingOrg = _buildOrg(
          dwellTimeSeconds: 300,
          maxKinematicSpeedKmh: 95.0,
        );
        when(
          () => mockRepository.findById(_orgId),
        ).thenAnswer((_) async => existingOrg);

        await handler.handle(
          _cmd(dwellTimeSeconds: 600, maxKinematicSpeedKmh: null),
        );

        final captured =
            verify(() => mockRepository.update(captureAny())).captured.first
                as Organization;

        // speed must remain at original value (95.0)
        expect(captured.capabilities.maxKinematicSpeedKmh, equals(95.0));
        // dwellTimeSeconds must be updated
        expect(captured.dwellTimeSeconds, equals(600));
      },
    );

    test(
      'updating both fields → both are changed in persisted entity',
      () async {
        final existingOrg = _buildOrg(
          dwellTimeSeconds: 300,
          maxKinematicSpeedKmh: 80.0,
        );
        when(
          () => mockRepository.findById(_orgId),
        ).thenAnswer((_) async => existingOrg);

        await handler.handle(
          _cmd(dwellTimeSeconds: 900, maxKinematicSpeedKmh: 180.0),
        );

        final captured =
            verify(() => mockRepository.update(captureAny())).captured.first
                as Organization;

        expect(captured.dwellTimeSeconds, equals(900));
        expect(captured.capabilities.maxKinematicSpeedKmh, equals(180.0));
      },
    );

    test(
      'updating neither field → org persisted with original values',
      () async {
        final existingOrg = _buildOrg(
          dwellTimeSeconds: 300,
          maxKinematicSpeedKmh: 80.0,
        );
        when(
          () => mockRepository.findById(_orgId),
        ).thenAnswer((_) async => existingOrg);

        await handler.handle(
          _cmd(dwellTimeSeconds: null, maxKinematicSpeedKmh: null),
        );

        final captured =
            verify(() => mockRepository.update(captureAny())).captured.first
                as Organization;

        expect(captured.dwellTimeSeconds, equals(300));
        expect(captured.capabilities.maxKinematicSpeedKmh, equals(80.0));
      },
    );

    test('other org fields (name, timezone, etc.) are never mutated', () async {
      final existingOrg = _buildOrg(dwellTimeSeconds: 300);
      when(
        () => mockRepository.findById(_orgId),
      ).thenAnswer((_) async => existingOrg);

      await handler.handle(_cmd(dwellTimeSeconds: 600));

      final captured =
          verify(() => mockRepository.update(captureAny())).captured.first
              as Organization;

      expect(captured.id, equals(_orgId));
      expect(captured.name, equals('Transportadora Teste'));
      expect(captured.timezone, equals('America/Sao_Paulo'));
      expect(captured.currencyCode, equals('BRL'));
      expect(captured.status, equals(OrgStatus.active));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BONUS: Tenant Validation (INV-1) Integration
  // ═══════════════════════════════════════════════════════════════════════════

  group('INV-1: Tenant Validation — Sovereignty Check', () {
    test(
      'tenant mismatch → SovereigntyViolationException propagates',
      () async {
        when(
          () => mockTenantValidator.assertTenantMatches(
            payloadOrgId: any(named: 'payloadOrgId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenThrow(
          const SovereigntyViolationException(
            payloadOrgId: _orgId,
            jwtOrgId: 'different-org-id',
          ),
        );

        await expectLater(
          handler.handle(_cmd(dwellTimeSeconds: 120)),
          throwsA(isA<SovereigntyViolationException>()),
        );

        verifyNever(() => mockRepository.findById(any()));
        verifyNever(() => mockRepository.update(any()));
      },
    );

    test('tenant validation is called BEFORE any other operation', () async {
      var callOrder = <String>[];

      when(
        () => mockTenantValidator.assertTenantMatches(
          payloadOrgId: any(named: 'payloadOrgId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) async => callOrder.add('tenant'));

      when(() => mockRepository.findById(any())).thenAnswer((_) async {
        callOrder.add('findById');
        return _buildOrg();
      });

      when(() => mockRepository.update(any())).thenAnswer((_) async {
        callOrder.add('update');
      });

      await handler.handle(_cmd(dwellTimeSeconds: 120));

      expect(callOrder.first, equals('tenant'));
    });
  });
}
