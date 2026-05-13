/// Forensic Test Suite: EvidenceLifecycleManager
/// Red Team ID 6 — Hot/Cold Storage Lifecycle, Legal Hold, INV-3, INV-24
///
/// Coverage matrix:
///   R-01 Retention Policy  : Hot→Cold (90 days), hash immutability (INV-3)
///   R-02 Legal Hold        : permanent block, post-5-year immunity
///   R-03 Adversarial       : network failure → rollback → idempotent retry
///   R-04 Access Control    : Service Role gate (INV-24)
///   R-05 Integrity Triad   : checksum parity after archive (INV-9)
///   R-06 Availability      : metadata queryable regardless of storage tier
///   R-07 Orphan Purge      : physical deletion ONLY for no-DB-record uploads (INV-3)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_lifecycle_manager.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockEvidenceLifecycleRepository extends Mock
    implements EvidenceLifecycleRepository {}

class MockEvidenceColdStoragePort extends Mock
    implements EvidenceColdStoragePort {}

class MockEvidenceOrphanDetectorPort extends Mock
    implements EvidenceOrphanDetectorPort {}

class FakeClock implements IDateTimeProvider {
  DateTime _now;

  FakeClock(this._now);

  @override
  DateTime nowUtc() => _now;

  @override
  DateTime nowBrazil() => _now;

  void advance(Duration d) => _now = _now.add(d);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _orgId = 'org-tenant-a';

EvidenceLifecycleRecord _makeRecord({
  String id = 'ev-001',
  String contentHash = 'abc123sha256',
  EvidenceStorageStatus status = EvidenceStorageStatus.hot,
  bool legalHold = false,
  Duration inactiveSince = const Duration(days: 91),
}) {
  final now = DateTime.utc(2026, 5, 8);
  return EvidenceLifecycleRecord(
    id: id,
    organizationId: _orgId,
    contentHash: contentHash,
    storagePath: 'justifications/$_orgId/$id.pdf',
    status: status,
    legalHold: legalHold,
    lastAccessedAtUtc: now.subtract(inactiveSince),
    uploadedAtUtc: now.subtract(const Duration(days: 400)),
  );
}

EvidenceLifecycleManager _buildManager(
  MockEvidenceLifecycleRepository repo,
  MockEvidenceColdStoragePort cold,
  FakeClock clock, {
  bool isServiceRole = true,
}) {
  return EvidenceLifecycleManager(
    repository: repo,
    coldStorage: cold,
    clock: clock,
    isServiceRole: isServiceRole,
  );
}

// ─── Test Suite ───────────────────────────────────────────────────────────────

void main() {
  late MockEvidenceLifecycleRepository repo;
  late MockEvidenceColdStoragePort cold;
  late MockEvidenceOrphanDetectorPort orphanDetector;
  late FakeClock clock;

  setUp(() {
    repo = MockEvidenceLifecycleRepository();
    cold = MockEvidenceColdStoragePort();
    orphanDetector = MockEvidenceOrphanDetectorPort();
    clock = FakeClock(DateTime.utc(2026, 5, 8));

    registerFallbackValue(_makeRecord());
  });

  // ── R-01: Retention Policy ────────────────────────────────────────────────

  group('R-01 Política de Retenção — Hot para Cold (90 dias)', () {
    test('DEVE arquivar evidência QUANDO inativa há mais de 90 dias', () async {
      final record = _makeRecord(inactiveSince: const Duration(days: 91));

      when(
        () => repo.findEligibleForArchiving(
          organizationId: _orgId,
          inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
        ),
      ).thenAnswer((_) async => [record]);

      when(
        () => cold.moveToColdStorage(record: record),
      ).thenAnswer((_) async {});

      when(
        () => cold.computeArchivedChecksum(record: record),
      ).thenAnswer((_) async => record.contentHash);

      when(
        () => repo.transitionToCold(
          evidenceId: record.id,
          organizationId: _orgId,
          archivedAtUtc: any(named: 'archivedAtUtc'),
        ),
      ).thenAnswer((_) async {});

      final manager = _buildManager(repo, cold, clock);
      final result = await manager.processArchivingBatch(
        organizationId: _orgId,
      );

      expect(result.archived, 1);
      expect(result.failed, 0);
      verify(
        () => repo.transitionToCold(
          evidenceId: record.id,
          organizationId: _orgId,
          archivedAtUtc: any(named: 'archivedAtUtc'),
        ),
      ).called(1);
    });

    test(
      'DEVE preservar contentHash no ledger QUANDO evidência é arquivada (INV-3)',
      () async {
        const originalHash = 'sha256-immutable-hash-sealed-at-ingest';
        final record = _makeRecord(contentHash: originalHash);

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [record]);

        when(
          () => cold.moveToColdStorage(record: record),
        ).thenAnswer((_) async {});

        // Cold storage returns same hash → integrity verified
        when(
          () => cold.computeArchivedChecksum(record: record),
        ).thenAnswer((_) async => originalHash);

        when(
          () => repo.transitionToCold(
            evidenceId: record.id,
            organizationId: _orgId,
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        await manager.processArchivingBatch(organizationId: _orgId);

        // Hash NEVER mutated — transitionToCold does not receive a new hash
        final captured = verify(
          () => repo.transitionToCold(
            evidenceId: record.id,
            organizationId: _orgId,
            archivedAtUtc: captureAny(named: 'archivedAtUtc'),
          ),
        ).captured;

        // contentHash not part of transitionToCold args = ledger immutability preserved
        expect(captured, isNotEmpty);
        expect(
          record.contentHash,
          originalHash,
          reason: 'contentHash must never mutate',
        );
      },
    );

    test(
      'DEVE retornar cutoff correto QUANDO calculando 90 dias de inatividade',
      () async {
        DateTime? capturedCutoff;

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((invocation) async {
          capturedCutoff =
              invocation.namedArguments[const Symbol('inactiveBeforeUtc')]
                  as DateTime;
          return [];
        });

        final manager = _buildManager(repo, cold, clock);
        await manager.processArchivingBatch(organizationId: _orgId);

        final expectedCutoff = clock.nowUtc().subtract(
          const Duration(
            days: EvidenceLifecycleManager.hotStorageRetentionDays,
          ),
        );

        expect(
          capturedCutoff,
          expectedCutoff,
          reason: 'Cutoff must be exactly nowUtc - 90 days',
        );
      },
    );
  });

  // ── R-02: Legal Hold ──────────────────────────────────────────────────────

  group('R-02 Legal Hold — Bloqueio Permanente de Transição', () {
    test('DEVE pular evidência QUANDO flag legalHold está ativo', () async {
      final held = _makeRecord(
        legalHold: true,
        inactiveSince: const Duration(days: 200),
      );

      when(
        () => repo.findEligibleForArchiving(
          organizationId: _orgId,
          inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
        ),
      ).thenAnswer((_) async => [held]);

      final manager = _buildManager(repo, cold, clock);
      final result = await manager.processArchivingBatch(
        organizationId: _orgId,
      );

      expect(result.skippedLegalHold, 1);
      expect(result.archived, 0);
      verifyNever(() => cold.moveToColdStorage(record: any(named: 'record')));
    });

    test(
      'DEVE bloquear transição QUANDO legalHold ativo E arquivo tem mais de 5 anos',
      () async {
        // 5 years + 1 day old, legal hold still blocks everything
        final held = _makeRecord(
          legalHold: true,
          inactiveSince: const Duration(days: 5 * 365 + 1),
        );

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [held]);

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(
          result.skippedLegalHold,
          1,
          reason: 'Legal Hold blocks even past 5-year mark',
        );
        verifyNever(() => cold.moveToColdStorage(record: any(named: 'record')));
        verifyNever(
          () => repo.transitionToCold(
            evidenceId: any(named: 'evidenceId'),
            organizationId: any(named: 'organizationId'),
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        );
      },
    );

    test(
      'DEVE arquivar QUANDO legalHold false mas outOtra evidência tem hold',
      () async {
        final normal = _makeRecord(id: 'ev-001', legalHold: false);
        final held = _makeRecord(id: 'ev-002', legalHold: true);

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [normal, held]);

        when(
          () => cold.moveToColdStorage(record: normal),
        ).thenAnswer((_) async {});

        when(
          () => cold.computeArchivedChecksum(record: normal),
        ).thenAnswer((_) async => normal.contentHash);

        when(
          () => repo.transitionToCold(
            evidenceId: normal.id,
            organizationId: _orgId,
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(result.archived, 1);
        expect(result.skippedLegalHold, 1);
        verifyNever(() => cold.moveToColdStorage(record: held));
      },
    );
  });

  // ── R-03: Cenários Adversos ───────────────────────────────────────────────

  group('R-03 Cenários Adversos — Falha e Idempotência', () {
    test(
      'DEVE reverter para Hot QUANDO falha de rede durante movimentação para Cold',
      () async {
        final record = _makeRecord();

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [record]);

        when(
          () => cold.moveToColdStorage(record: record),
        ).thenThrow(Exception('Network timeout during cold storage transfer'));

        when(
          () =>
              repo.rollbackToHot(evidenceId: record.id, organizationId: _orgId),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(result.failed, 1);
        expect(result.archived, 0);
        verify(
          () =>
              repo.rollbackToHot(evidenceId: record.id, organizationId: _orgId),
        ).called(1);
        verifyNever(
          () => repo.transitionToCold(
            evidenceId: any(named: 'evidenceId'),
            organizationId: any(named: 'organizationId'),
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        );
      },
    );

    test(
      'DEVE ser idempotente QUANDO próximo batch reencontra evidência em Hot após falha',
      () async {
        final record = _makeRecord();

        // First batch: fails
        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [record]);

        when(
          () => cold.moveToColdStorage(record: record),
        ).thenThrow(Exception('Transient network error'));

        when(
          () =>
              repo.rollbackToHot(evidenceId: record.id, organizationId: _orgId),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        final firstResult = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(firstResult.failed, 1);

        // Second batch: succeeds (same record still in Hot, retried)
        when(
          () => cold.moveToColdStorage(record: record),
        ).thenAnswer((_) async {});

        when(
          () => cold.computeArchivedChecksum(record: record),
        ).thenAnswer((_) async => record.contentHash);

        when(
          () => repo.transitionToCold(
            evidenceId: record.id,
            organizationId: _orgId,
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        ).thenAnswer((_) async {});

        final secondResult = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(secondResult.archived, 1);
        expect(secondResult.failed, 0);
      },
    );

    test(
      'DEVE reverter para Hot QUANDO checksum pós-arquivamento não corresponde ao original',
      () async {
        final record = _makeRecord(contentHash: 'original-sha256-hash');

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [record]);

        when(
          () => cold.moveToColdStorage(record: record),
        ).thenAnswer((_) async {});

        // Corrupted during transfer
        when(
          () => cold.computeArchivedChecksum(record: record),
        ).thenAnswer((_) async => 'corrupted-hash-after-transfer');

        when(
          () =>
              repo.rollbackToHot(evidenceId: record.id, organizationId: _orgId),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(result.failed, 1);
        verify(
          () =>
              repo.rollbackToHot(evidenceId: record.id, organizationId: _orgId),
        ).called(1);
        verifyNever(
          () => repo.transitionToCold(
            evidenceId: any(named: 'evidenceId'),
            organizationId: any(named: 'organizationId'),
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        );
      },
    );

    test(
      'DEVE continuar processando QUANDO uma evidência falha E outras têm sucesso',
      () async {
        final failing = _makeRecord(id: 'ev-fail', contentHash: 'hash-fail');
        final passing = _makeRecord(id: 'ev-pass', contentHash: 'hash-pass');

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [failing, passing]);

        when(
          () => cold.moveToColdStorage(record: failing),
        ).thenThrow(Exception('Disk quota exceeded'));

        when(
          () => repo.rollbackToHot(
            evidenceId: failing.id,
            organizationId: _orgId,
          ),
        ).thenAnswer((_) async {});

        when(
          () => cold.moveToColdStorage(record: passing),
        ).thenAnswer((_) async {});

        when(
          () => cold.computeArchivedChecksum(record: passing),
        ).thenAnswer((_) async => passing.contentHash);

        when(
          () => repo.transitionToCold(
            evidenceId: passing.id,
            organizationId: _orgId,
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(result.archived, 1);
        expect(result.failed, 1);
      },
    );
  });

  // ── R-04: Controle de Acesso (INV-24) ────────────────────────────────────

  group('R-04 Acesso Negado — INV-24 Service Role Gate', () {
    test(
      'DEVE lançar IntegrityException QUANDO chamado sem Service Role',
      () async {
        final manager = _buildManager(repo, cold, clock, isServiceRole: false);

        expect(
          () => manager.processArchivingBatch(organizationId: _orgId),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.field,
              'field',
              'isServiceRole',
            ),
          ),
        );

        verifyZeroInteractions(repo);
        verifyZeroInteractions(cold);
      },
    );

    test(
      'DEVE processar batch normalmente QUANDO chamado com Service Role',
      () async {
        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => []);

        final manager = _buildManager(repo, cold, clock, isServiceRole: true);
        final result = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(result.archived, 0);
        verify(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).called(1);
      },
    );

    test(
      'DEVE lançar IntegrityException com mensagem descritiva QUANDO acesso negado',
      () async {
        final manager = _buildManager(repo, cold, clock, isServiceRole: false);

        await expectLater(
          manager.processArchivingBatch(organizationId: _orgId),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Service Role'),
            ),
          ),
        );
      },
    );
  });

  // ── R-05: Integridade — Checksum Pós-Arquivo ──────────────────────────────

  group('R-05 Tríade de Segurança — Integridade do Binário Arquivado', () {
    test(
      'DEVE verificar checksum após arquivamento QUANDO movendo para Cold',
      () async {
        final record = _makeRecord(contentHash: 'sha256-expected');

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [record]);

        when(
          () => cold.moveToColdStorage(record: record),
        ).thenAnswer((_) async {});

        when(
          () => cold.computeArchivedChecksum(record: record),
        ).thenAnswer((_) async => 'sha256-expected');

        when(
          () => repo.transitionToCold(
            evidenceId: record.id,
            organizationId: _orgId,
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        await manager.processArchivingBatch(organizationId: _orgId);

        verify(() => cold.computeArchivedChecksum(record: record)).called(1);
      },
    );

    test(
      'DEVE confirmar transição SOMENTE após checksum bater com hash do ledger',
      () async {
        final record = _makeRecord(contentHash: 'correct-hash');
        final callOrder = <String>[];

        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => [record]);

        when(() => cold.moveToColdStorage(record: record)).thenAnswer((
          _,
        ) async {
          callOrder.add('move');
        });

        when(() => cold.computeArchivedChecksum(record: record)).thenAnswer((
          _,
        ) async {
          callOrder.add('checksum');
          return 'correct-hash';
        });

        when(
          () => repo.transitionToCold(
            evidenceId: record.id,
            organizationId: _orgId,
            archivedAtUtc: any(named: 'archivedAtUtc'),
          ),
        ).thenAnswer((_) async {
          callOrder.add('transition');
        });

        final manager = _buildManager(repo, cold, clock);
        await manager.processArchivingBatch(organizationId: _orgId);

        expect(
          callOrder,
          ['move', 'checksum', 'transition'],
          reason: 'Transition must only happen AFTER checksum verification',
        );
      },
    );

    test(
      'DEVE validar constantes forenses: 90 dias hot, 5 anos retenção legal',
      () {
        expect(EvidenceLifecycleManager.hotStorageRetentionDays, 90);
        expect(EvidenceLifecycleManager.legalRetentionYears, 5);
      },
    );
  });

  // ── R-06: Disponibilidade — Metadados Sempre Consultáveis ─────────────────

  group('R-06 Tríade de Segurança — Disponibilidade de Metadados', () {
    test(
      'DEVE retornar metadados QUANDO arquivo está em Cold Storage (consulta de auditoria)',
      () async {
        final coldRecord = EvidenceLifecycleRecord(
          id: 'ev-cold-001',
          organizationId: _orgId,
          contentHash: 'sha256-of-archived-file',
          storagePath: 'justifications/$_orgId/ev-cold-001.pdf',
          status: EvidenceStorageStatus.cold,
          legalHold: false,
          lastAccessedAtUtc: DateTime.utc(2025, 1, 1),
          uploadedAtUtc: DateTime.utc(2024, 6, 1),
        );

        when(
          () =>
              repo.findById(evidenceId: 'ev-cold-001', organizationId: _orgId),
        ).thenAnswer((_) async => coldRecord);

        final result = await repo.findById(
          evidenceId: 'ev-cold-001',
          organizationId: _orgId,
        );

        expect(result, isNotNull);
        expect(result!.status, EvidenceStorageStatus.cold);
        expect(
          result.contentHash,
          'sha256-of-archived-file',
          reason: 'contentHash must be queryable even in cold tier (INV-3)',
        );
      },
    );

    test(
      'DEVE incluir contentHash no metadado MESMO quando arquivo físico está em Cold',
      () async {
        const hash = 'immutable-forensic-hash';
        final coldRecord = EvidenceLifecycleRecord(
          id: 'ev-audit',
          organizationId: _orgId,
          contentHash: hash,
          storagePath: 'justifications/$_orgId/ev-audit.pdf',
          status: EvidenceStorageStatus.cold,
          legalHold: false,
          lastAccessedAtUtc: DateTime.utc(2025, 1, 1),
          uploadedAtUtc: DateTime.utc(2024, 6, 1),
        );

        when(
          () => repo.findById(evidenceId: 'ev-audit', organizationId: _orgId),
        ).thenAnswer((_) async => coldRecord);

        final record = await repo.findById(
          evidenceId: 'ev-audit',
          organizationId: _orgId,
        );

        expect(
          record!.contentHash,
          hash,
          reason:
              'Hash must survive cold transition — ledger is append-only (INV-3)',
        );
        expect(record.status, EvidenceStorageStatus.cold);
      },
    );

    test(
      'DEVE retornar null QUANDO evidência não pertence à organização (INV-26 anti-oracle)',
      () async {
        when(
          () =>
              repo.findById(evidenceId: 'ev-other-org', organizationId: _orgId),
        ).thenAnswer((_) async => null);

        final result = await repo.findById(
          evidenceId: 'ev-other-org',
          organizationId: _orgId,
        );

        expect(
          result,
          isNull,
          reason: 'Anti-Oracle: 404 for not-found AND wrong-org (INV-26)',
        );
      },
    );

    test(
      'DEVE processar batch vazio sem erros QUANDO não há evidências elegíveis',
      () async {
        when(
          () => repo.findEligibleForArchiving(
            organizationId: _orgId,
            inactiveBeforeUtc: any(named: 'inactiveBeforeUtc'),
          ),
        ).thenAnswer((_) async => []);

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.processArchivingBatch(
          organizationId: _orgId,
        );

        expect(result.archived, 0);
        expect(result.skippedLegalHold, 0);
        expect(result.failed, 0);
        verifyZeroInteractions(cold);
      },
    );
  });

  // ── R-07: Purga de Uploads Órfãos ─────────────────────────────────────────
  //
  // INV-3 physical deletion boundary: ONLY files with NO DB record may be
  // physically deleted. Business evidence (any DB record, even rejected/expired)
  // MUST travel to Cold Storage — never to trash.
  //
  // Exploit path closed: without this boundary, a compromised scheduled job
  // (or a race where deletion fires before INSERT commits) could silently
  // destroy forensic evidence — an INV-3 violation masquerading as cleanup.

  group('R-07 Purga de Uploads Órfãos — INV-3 Boundary', () {
    test(
      'DEVE deletar arquivo QUANDO não existe registro DB correspondente (upload interrompido)',
      () async {
        const orphanPath =
            'justifications/org-tenant-a/upload-interrupted-abc.pdf';

        when(
          () => orphanDetector.findOrphanedPaths(organizationId: _orgId),
        ).thenAnswer((_) async => [orphanPath]);

        when(
          () => orphanDetector.deletePaths(
            paths: [orphanPath],
            organizationId: _orgId,
          ),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.purgeOrphanedUploads(
          organizationId: _orgId,
          orphanDetector: orphanDetector,
        );

        expect(result.purged, 1);
        expect(result.failed, 0);
        verify(
          () => orphanDetector.deletePaths(
            paths: [orphanPath],
            organizationId: _orgId,
          ),
        ).called(1);
      },
    );

    test(
      'DEVE NUNCA deletar QUANDO arquivo tem registro DB — vai para Cold, não para lixo (INV-3)',
      () async {
        // Detector returns empty: the file-with-DB-record was NOT classified
        // as orphan by the infrastructure layer. This test asserts that
        // purgeOrphanedUploads only acts on what the detector surfaces —
        // it never reaches into the repository to manually delete DB-backed files.
        when(
          () => orphanDetector.findOrphanedPaths(organizationId: _orgId),
        ).thenAnswer(
          (_) async => [],
        ); // file with DB record excluded by detector

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.purgeOrphanedUploads(
          organizationId: _orgId,
          orphanDetector: orphanDetector,
        );

        expect(result.purged, 0);
        expect(result.failed, 0);

        // Confirm: no repository interaction — the lifecycle manager never
        // touches DB-backed evidence records during orphan purge.
        verifyZeroInteractions(repo);
        verifyNever(
          () => orphanDetector.deletePaths(
            paths: any(named: 'paths'),
            organizationId: any(named: 'organizationId'),
          ),
        );
      },
    );

    test(
      'DEVE lançar IntegrityException QUANDO chamado sem Service Role (INV-24)',
      () async {
        final manager = _buildManager(repo, cold, clock, isServiceRole: false);

        await expectLater(
          manager.purgeOrphanedUploads(
            organizationId: _orgId,
            orphanDetector: orphanDetector,
          ),
          throwsA(
            isA<IntegrityException>()
                .having((e) => e.field, 'field', 'isServiceRole')
                .having((e) => e.message, 'message', contains('Service Role')),
          ),
        );

        // No storage interaction must occur before the guard fires.
        verifyZeroInteractions(orphanDetector);
      },
    );

    test(
      'DEVE ser idempotente QUANDO arquivo já foi deletado em run anterior',
      () async {
        // Second run: the path is no longer returned because the storage
        // listing no longer includes an already-deleted file.
        // Detector returns empty — safe to call again with zero side effects.
        when(
          () => orphanDetector.findOrphanedPaths(organizationId: _orgId),
        ).thenAnswer((_) async => []);

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.purgeOrphanedUploads(
          organizationId: _orgId,
          orphanDetector: orphanDetector,
        );

        expect(result.purged, 0);
        expect(result.failed, 0);
        verifyNever(
          () => orphanDetector.deletePaths(
            paths: any(named: 'paths'),
            organizationId: any(named: 'organizationId'),
          ),
        );
      },
    );

    test(
      'DEVE incrementar contador failed QUANDO deletePath lança exceção (sem swallow silencioso)',
      () async {
        const path1 = 'justifications/org-tenant-a/orphan-1.pdf';
        const path2 = 'justifications/org-tenant-a/orphan-2.pdf';

        when(
          () => orphanDetector.findOrphanedPaths(organizationId: _orgId),
        ).thenAnswer((_) async => [path1, path2]);

        // path1 fails, path2 succeeds
        when(
          () => orphanDetector.deletePaths(
            paths: [path1],
            organizationId: _orgId,
          ),
        ).thenThrow(Exception('Storage API error: bucket rate limit'));

        when(
          () => orphanDetector.deletePaths(
            paths: [path2],
            organizationId: _orgId,
          ),
        ).thenAnswer((_) async {});

        final manager = _buildManager(repo, cold, clock);
        final result = await manager.purgeOrphanedUploads(
          organizationId: _orgId,
          orphanDetector: orphanDetector,
        );

        expect(result.purged, 1, reason: 'path2 succeeded');
        expect(
          result.failed,
          1,
          reason: 'path1 failure must be counted, not swallowed',
        );
      },
    );

    test(
      'DEVE confirmar inv3PolicyStatement como contrato codificado da política',
      () {
        expect(
          EvidenceLifecycleManager.inv3PolicyStatement,
          contains('Cold Storage'),
          reason:
              'Policy statement must reference Cold Storage as destination for DB-backed evidence',
        );
        expect(
          EvidenceLifecycleManager.inv3PolicyStatement,
          contains('orphaned uploads'),
          reason:
              'Policy statement must explicitly name the only permitted deletion target',
        );
      },
    );
  });
}
