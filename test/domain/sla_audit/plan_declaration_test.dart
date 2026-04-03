import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/contractual_plan_declared_event.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';

void main() {
  // ── Helpers ──────────────────────────────────────────────────
  ContractualServiceExecution makeService({
    String contractId = 'contract-1',
    DateTime? start,
    DateTime? end,
    double startLat = -23.5505,
    double startLng = -46.6333,
    int startRadius = 100,
    double endLat = -23.5600,
    double endLng = -46.6400,
    int endRadius = 100,
    Money contractualValue = const Money(15000),
    int noShowPenaltyBps = 15000,
  }) {
    final s = start ?? DateTime.utc(2026, 3, 1, 6, 0);
    final e = end ?? s.add(const Duration(hours: 1));
    return ContractualServiceExecution.create(
      contractId: contractId,
      scheduledStartTimeUtc: s,
      scheduledEndTimeUtc: e,
      startLatitude: startLat,
      startLongitude: startLng,
      startRadiusMeters: startRadius,
      endLatitude: endLat,
      endLongitude: endLng,
      endRadiusMeters: endRadius,
      contractualValue: contractualValue,
      noShowPenaltyBps: noShowPenaltyBps,
    );
  }

  PlanDeclaration makeDeclaration({
    String contractId = 'contract-1',
    DateTime? declaredAt,
    String userId = 'user-1',
    int version = 1,
    String hash = 'abc123hash',
    List<ContractualServiceExecution>? services,
  }) {
    return PlanDeclaration.create(
      ruleSnapshot: const RuleSnapshot([]),
      organizationId: 'org-1',
      contractId: contractId,
      declaredAtUtc: declaredAt ?? DateTime.utc(2026, 2, 25),
      declaredByUserId: userId,
      planVersion: version,
      originalFileHash: hash,
      services: services ?? [makeService()],
    );
  }

  // ── ContractualServiceExecution Tests ────────────────────────
  group('ContractualServiceExecution', () {
    test('create() produces entity with deterministic SET', () {
      final a = makeService();
      final b = makeService(); // same inputs
      expect(a.setId, equals(b.setId));
      expect(a.setId, isNotEmpty);
    });

    test('different inputs produce different SETs', () {
      final a = makeService(start: DateTime.utc(2026, 3, 1, 6, 0));
      final b = makeService(start: DateTime.utc(2026, 3, 1, 8, 0));
      expect(a.setId, isNot(equals(b.setId)));
    });

    test('equality is based exclusively on setId', () {
      final a = makeService();
      final b = makeService(); // same setId
      expect(a, equals(b));
    });

    test('throws on scheduledEndTimeUtc <= scheduledStartTimeUtc', () {
      final t = DateTime.utc(2026, 3, 1, 6, 0);
      expect(
        () => makeService(start: t, end: t),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => makeService(start: t, end: t.subtract(const Duration(hours: 1))),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on invalid startLatitude', () {
      expect(() => makeService(startLat: -91), throwsA(isA<DomainException>()));
      expect(() => makeService(startLat: 91), throwsA(isA<DomainException>()));
    });

    test('throws on invalid endLatitude', () {
      expect(() => makeService(endLat: -91), throwsA(isA<DomainException>()));
    });

    test('throws on invalid startLongitude', () {
      expect(
        () => makeService(startLng: -181),
        throwsA(isA<DomainException>()),
      );
      expect(() => makeService(startLng: 181), throwsA(isA<DomainException>()));
    });

    test('throws on invalid endLongitude', () {
      expect(() => makeService(endLng: 181), throwsA(isA<DomainException>()));
    });

    test('throws on startRadiusMeters <= 0', () {
      expect(
        () => makeService(startRadius: 0),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => makeService(startRadius: -5),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on endRadiusMeters <= 0', () {
      expect(() => makeService(endRadius: 0), throwsA(isA<DomainException>()));
    });
  });

  // ── PlanDeclaration Tests ────────────────────────────────────
  group('PlanDeclaration', () {
    test('create() produces aggregate with correct fields', () {
      final pd = makeDeclaration();

      expect(pd.id, isNotEmpty);
      expect(pd.contractId, 'contract-1');
      expect(pd.declaredByUserId, 'user-1');
      expect(pd.planVersion, 1);
      expect(pd.originalFileHash, 'abc123hash');
      expect(pd.services, hasLength(1));
    });

    test('create() emits exactly one ContractualPlanDeclaredEvent', () {
      final pd = makeDeclaration();

      expect(pd.domainEvents, hasLength(1));
      expect(pd.domainEvents.first, isA<ContractualPlanDeclaredEvent>());
    });

    test('emitted event contains correct fields', () {
      final pd = makeDeclaration(
        contractId: 'c-99',
        userId: 'u-42',
        version: 3,
      );

      final event = pd.domainEvents.first as ContractualPlanDeclaredEvent;

      expect(event.planDeclarationId, pd.id);
      expect(event.contractId, 'c-99');
      expect(event.declaredByUserId, 'u-42');
      expect(event.planVersion, 3);
      expect(event.totalServicesDeclared, 1);
      expect(
        event.occurredAtUtc.isBefore(
          DateTime.now().toUtc().add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('throws on empty contractId', () {
      expect(
        () => makeDeclaration(contractId: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on empty declaredByUserId', () {
      expect(
        () => makeDeclaration(userId: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on empty originalFileHash', () {
      expect(() => makeDeclaration(hash: ''), throwsA(isA<DomainException>()));
    });

    test('throws on empty services list', () {
      expect(
        () => makeDeclaration(services: []),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on duplicate SET in services', () {
      final svc = makeService();
      expect(
        () => makeDeclaration(services: [svc, svc]),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on future declaredAtUtc', () {
      expect(
        () => makeDeclaration(
          declaredAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('services list is unmodifiable externally', () {
      final pd = makeDeclaration();
      expect(
        () => pd.services.add(makeService()),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('domainEvents list is unmodifiable externally', () {
      final pd = makeDeclaration();
      // UnmodifiableListView will reject any mutation attempt.
      // The exact error depends on whether the type mismatch or
      // the unmodifiable check fires first, so we accept any throw.
      expect(
        () => pd.domainEvents.add(pd.domainEvents.first),
        throwsUnsupportedError,
      );
    });

    test('accepts multiple unique services', () {
      final services = [
        makeService(start: DateTime.utc(2026, 3, 1, 6, 0)),
        makeService(start: DateTime.utc(2026, 3, 1, 8, 0)),
        makeService(start: DateTime.utc(2026, 3, 1, 10, 0)),
      ];

      final pd = makeDeclaration(services: services);
      expect(pd.services, hasLength(3));
    });
  });
}
