/// **Validates: Requirements 9.5**
///
/// Property 12: Append-Only Idempotency (INV-3)
///
/// For any provider that performs write operations on append-only ledger tables,
/// executing the same command twice with the same `idempotencyKey` SHALL result
/// in exactly one record being created (not two), ensuring safety under
/// automatic retry.
///
/// Strategy: Source-code structural verification.
///
/// 1. All handlers that write to append-only tables use one of the three
///    idempotency mechanisms:
///    a) IdempotentHandlerMixin (CloseContractHandler, DeclareContractualPlanHandler)
///    b) Status guards — checking entry status before proceeding
///       (ApproveSanctionHandler, RejectSanctionHandler,
///        ApproveJustificationHandler, RejectJustificationHandler)
///    c) Deterministic IDs (not used by current handlers)
/// 2. Each handler has at least one test that executes the same operation twice.
/// 3. ContractCommandState generates a stable idempotencyKey in build() that
///    persists across retries.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 12: Append-Only Idempotency (INV-3)

/// Describes a handler that writes to append-only ledger tables and its
/// expected idempotency mechanism.
class AppendOnlyHandlerSpec {
  /// Relative path to the handler source file from project root.
  final String handlerFilePath;

  /// Human-readable name for test output.
  final String displayName;

  /// The idempotency mechanism used by this handler.
  final IdempotencyMechanism mechanism;

  /// Relative path to the test file that exercises idempotency.
  final String testFilePath;

  /// Pattern that proves the idempotency mechanism is present in source.
  final String mechanismMarker;

  /// Pattern in the test file that proves double-execution is tested.
  final String doubleExecutionMarker;

  const AppendOnlyHandlerSpec({
    required this.handlerFilePath,
    required this.displayName,
    required this.mechanism,
    required this.testFilePath,
    required this.mechanismMarker,
    required this.doubleExecutionMarker,
  });

  @override
  String toString() => displayName;
}

/// The three idempotency mechanisms recognized by INV-3.
enum IdempotencyMechanism {
  /// Uses `IdempotentHandlerMixin.executeWithIdempotency()` for atomic
  /// acquisition, cached error replays, and dual-write self-healing.
  idempotentHandlerMixin,

  /// Uses a status guard (e.g., `if (entry.status != pending) throw ...`)
  /// to reject duplicate operations on already-processed entities.
  statusGuard,

  /// Uses deterministic IDs (e.g., content-hash-based UUIDs) to ensure
  /// that duplicate inserts are rejected by the database unique constraint.
  deterministicId,
}

/// All 6 handlers that write to append-only ledger tables.
const _appendOnlyHandlers = <AppendOnlyHandlerSpec>[
  AppendOnlyHandlerSpec(
    handlerFilePath: 'lib/application/sla_audit/close_contract_handler.dart',
    displayName: 'CloseContractHandler',
    mechanism: IdempotencyMechanism.idempotentHandlerMixin,
    testFilePath: 'test/application/sla_audit/close_contract_handler_test.dart',
    mechanismMarker: 'IdempotentHandlerMixin',
    doubleExecutionMarker: 'idemp-double',
  ),
  AppendOnlyHandlerSpec(
    handlerFilePath:
        'lib/application/sla_audit/declare_contractual_plan_handler.dart',
    displayName: 'DeclareContractualPlanHandler',
    mechanism: IdempotencyMechanism.idempotentHandlerMixin,
    testFilePath:
        'test/application/sla_audit/phase5_contract_lifecycle_compliance_test.dart',
    mechanismMarker: 'IdempotentHandlerMixin',
    doubleExecutionMarker: 'idempotency',
  ),
  AppendOnlyHandlerSpec(
    handlerFilePath: 'lib/application/sla_audit/approve_sanction_handler.dart',
    displayName: 'ApproveSanctionHandler',
    mechanism: IdempotencyMechanism.statusGuard,
    testFilePath:
        'test/application/sla_audit/approve_sanction_handler_test.dart',
    mechanismMarker: 'entry.status != SanctionReviewStatus.pending',
    doubleExecutionMarker: 'already applied',
  ),
  AppendOnlyHandlerSpec(
    handlerFilePath: 'lib/application/sla_audit/reject_sanction_handler.dart',
    displayName: 'RejectSanctionHandler',
    mechanism: IdempotencyMechanism.statusGuard,
    testFilePath:
        'test/application/sla_audit/reject_sanction_handler_test.dart',
    mechanismMarker: 'entry.status != SanctionReviewStatus.pending',
    doubleExecutionMarker: 'already rejected',
  ),
  AppendOnlyHandlerSpec(
    handlerFilePath:
        'lib/application/sla_audit/justification/approve_justification_handler.dart',
    displayName: 'ApproveJustificationHandler',
    mechanism: IdempotencyMechanism.statusGuard,
    testFilePath:
        'test/application/sla_audit/justification/approve_justification_handler_test.dart',
    mechanismMarker: 'justification.isPending',
    doubleExecutionMarker: 'already approved',
  ),
  AppendOnlyHandlerSpec(
    handlerFilePath:
        'lib/application/sla_audit/justification/reject_justification_handler.dart',
    displayName: 'RejectJustificationHandler',
    mechanism: IdempotencyMechanism.statusGuard,
    testFilePath:
        'test/application/sla_audit/justification/reject_justification_handler_test.dart',
    mechanismMarker: 'justification.isPending',
    doubleExecutionMarker: 'already processed',
  ),
];

/// All handler display names for Glados selection.
final _allHandlerNames = _appendOnlyHandlers.map((h) => h.displayName).toList();

/// Path to the ContractCommandState file that generates idempotencyKey.
const _contractCommandStatePath =
    'lib/state/notifiers/contract_command_state.dart';

/// Path to the ContractCommandNotifier that uses the idempotencyKey.
const _contractCommandNotifierPath =
    'lib/state/notifiers/contract_command_notifier.dart';

void main() {
  group('Property 12: Append-Only Idempotency (INV-3)', () {
    // ── Sub-property 1: Handler source files exist ──────────────────────
    Glados(any.choose(_allHandlerNames)).test(
      'each append-only handler source file exists',
      (handlerName) {
        final spec = _appendOnlyHandlers.firstWhere(
          (h) => h.displayName == handlerName,
        );
        final file = File(spec.handlerFilePath);

        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Handler source file ${spec.handlerFilePath} must exist '
              'for INV-3 verification',
        );
      },
    );

    // ── Sub-property 2: Each handler uses an idempotency mechanism ──────
    Glados(any.choose(_allHandlerNames)).test(
      'each handler uses one of the three idempotency mechanisms',
      (handlerName) {
        final spec = _appendOnlyHandlers.firstWhere(
          (h) => h.displayName == handlerName,
        );
        final content = File(spec.handlerFilePath).readAsStringSync();

        expect(
          content.contains(spec.mechanismMarker),
          isTrue,
          reason:
              '${spec.displayName} must contain idempotency mechanism marker '
              '"${spec.mechanismMarker}" (INV-3). '
              'Mechanism: ${spec.mechanism.name}',
        );
      },
    );

    // ── Sub-property 3: IdempotentHandlerMixin handlers use
    //    executeWithIdempotency ──────────────────────────────────────────
    Glados(any.choose(_allHandlerNames)).test(
      'IdempotentHandlerMixin handlers call executeWithIdempotency',
      (handlerName) {
        final spec = _appendOnlyHandlers.firstWhere(
          (h) => h.displayName == handlerName,
        );

        // Only applicable to handlers using IdempotentHandlerMixin
        if (spec.mechanism != IdempotencyMechanism.idempotentHandlerMixin) {
          return;
        }

        final content = File(spec.handlerFilePath).readAsStringSync();

        expect(
          content.contains('executeWithIdempotency'),
          isTrue,
          reason:
              '${spec.displayName} uses IdempotentHandlerMixin but does not '
              'call executeWithIdempotency (INV-3 violation)',
        );

        // Must also pass an idempotencyKey
        expect(
          content.contains('idempotencyKey'),
          isTrue,
          reason:
              '${spec.displayName} must pass idempotencyKey to '
              'executeWithIdempotency (INV-3)',
        );
      },
    );

    // ── Sub-property 4: Status guard handlers check status before write ─
    Glados(any.choose(_allHandlerNames)).test(
      'status guard handlers reject non-pending entries before ledger write',
      (handlerName) {
        final spec = _appendOnlyHandlers.firstWhere(
          (h) => h.displayName == handlerName,
        );

        // Only applicable to status guard handlers
        if (spec.mechanism != IdempotencyMechanism.statusGuard) return;

        final content = File(spec.handlerFilePath).readAsStringSync();

        // The status check must appear BEFORE the ledger append
        final statusCheckIndex = content.indexOf(spec.mechanismMarker);
        final ledgerAppendIndex = content.indexOf('_ledger.append');

        expect(
          statusCheckIndex,
          greaterThanOrEqualTo(0),
          reason:
              '${spec.displayName} must contain status guard '
              '"${spec.mechanismMarker}"',
        );

        expect(
          ledgerAppendIndex,
          greaterThanOrEqualTo(0),
          reason: '${spec.displayName} must append to the ledger',
        );

        expect(
          statusCheckIndex,
          lessThan(ledgerAppendIndex),
          reason:
              '${spec.displayName}: status guard must appear BEFORE '
              'ledger append to prevent duplicate writes (INV-3)',
        );
      },
    );

    // ── Sub-property 5: Each handler has a test for double-execution ────
    Glados(
      any.choose(_allHandlerNames),
    ).test('each handler has at least one test exercising double-execution', (
      handlerName,
    ) {
      final spec = _appendOnlyHandlers.firstWhere(
        (h) => h.displayName == handlerName,
      );
      final testFile = File(spec.testFilePath);

      expect(
        testFile.existsSync(),
        isTrue,
        reason:
            'Test file ${spec.testFilePath} must exist for '
            '${spec.displayName} idempotency verification',
      );

      final testContent = testFile.readAsStringSync();

      expect(
        testContent.contains(spec.doubleExecutionMarker),
        isTrue,
        reason:
            '${spec.displayName} test file must contain a test exercising '
            'double-execution (marker: "${spec.doubleExecutionMarker}"). '
            'INV-3 requires at least one test per handler that executes '
            'the same operation twice and verifies only one record is created.',
      );
    });

    // ── Sub-property 6: All handlers append to immutable ledger ─────────
    Glados(
      any.choose(_allHandlerNames),
    ).test('each handler writes to the append-only ledger', (handlerName) {
      final spec = _appendOnlyHandlers.firstWhere(
        (h) => h.displayName == handlerName,
      );
      final content = File(spec.handlerFilePath).readAsStringSync();

      // All handlers must reference the ledger repository
      final hasLedgerField =
          content.contains('SlaAuditLedgerRepository') ||
          content.contains('_ledger');

      expect(
        hasLedgerField,
        isTrue,
        reason:
            '${spec.displayName} must reference SlaAuditLedgerRepository '
            'to write to the append-only ledger (INV-3)',
      );

      // All handlers must call append on the ledger
      expect(
        content.contains('_ledger.append') || content.contains('ledger.append'),
        isTrue,
        reason:
            '${spec.displayName} must call append on the ledger '
            'repository (INV-3)',
      );
    });

    // ── Sub-property 7: ContractCommandState generates stable
    //    idempotencyKey in build() ───────────────────────────────────────
    Glados(any.intInRange(0, 2)).test(
      'ContractCommandState generates stable idempotencyKey in build()',
      (_) {
        final stateFile = File(_contractCommandStatePath);

        expect(
          stateFile.existsSync(),
          isTrue,
          reason:
              'ContractCommandState file must exist at '
              '$_contractCommandStatePath',
        );

        final stateContent = stateFile.readAsStringSync();

        // Must contain idempotencyKey field
        expect(
          stateContent.contains('final String idempotencyKey'),
          isTrue,
          reason:
              'ContractCommandState must have a final String idempotencyKey '
              'field (INV-33)',
        );

        // Must use Uuid for generation
        expect(
          stateContent.contains('Uuid'),
          isTrue,
          reason:
              'ContractCommandState must use Uuid for idempotencyKey '
              'generation (INV-33)',
        );

        // The copyWith must preserve idempotencyKey
        expect(
          stateContent.contains('idempotencyKey: idempotencyKey'),
          isTrue,
          reason:
              'ContractCommandState.copyWith must preserve the '
              'idempotencyKey across state transitions (INV-33)',
        );
      },
    );

    // ── Sub-property 8: ContractCommandNotifier.build() generates key ───
    Glados(any.intInRange(0, 2)).test(
      'ContractCommandNotifier.build() generates idempotencyKey on creation',
      (_) {
        final notifierFile = File(_contractCommandNotifierPath);

        expect(
          notifierFile.existsSync(),
          isTrue,
          reason:
              'ContractCommandNotifier file must exist at '
              '$_contractCommandNotifierPath',
        );

        final notifierContent = notifierFile.readAsStringSync();

        // build() must create a ContractCommandState with idempotencyKey
        expect(
          notifierContent.contains('ContractCommandState(idempotencyKey:'),
          isTrue,
          reason:
              'ContractCommandNotifier.build() must create '
              'ContractCommandState with an idempotencyKey (INV-33)',
        );

        // build() must use Uuid().v4() for key generation
        expect(
          notifierContent.contains('Uuid().v4()'),
          isTrue,
          reason:
              'ContractCommandNotifier.build() must generate idempotencyKey '
              'using Uuid().v4() (INV-33)',
        );

        // The notifier must pass state.idempotencyKey to commands
        expect(
          notifierContent.contains('state.idempotencyKey'),
          isTrue,
          reason:
              'ContractCommandNotifier must pass state.idempotencyKey to '
              'command handlers, ensuring the same key is reused across '
              'retries (INV-33)',
        );
      },
    );

    // ── Sub-property 9: IdempotencyKey persists across retries ──────────
    Glados(any.intInRange(0, 2)).test(
      'idempotencyKey persists across retries (not regenerated on error)',
      (_) {
        final notifierContent = File(
          _contractCommandNotifierPath,
        ).readAsStringSync();

        // The notifier must NOT regenerate the key on error.
        // Only onFormChanged() with explicit user action generates a new key.
        // Verify that state mutations (setLoading, setError) use copyWith
        // which preserves the key.
        expect(
          notifierContent.contains('state.copyWith(status:'),
          isTrue,
          reason:
              'ContractCommandNotifier must use state.copyWith(status:) '
              'for state transitions, which preserves idempotencyKey '
              'across retries (INV-33)',
        );

        // Verify onFormChanged only generates new key on error state
        expect(
          notifierContent.contains('state.status is AsyncError'),
          isTrue,
          reason:
              'ContractCommandNotifier.onFormChanged() must only generate '
              'a new key when current state is AsyncError (user corrected '
              'data), not on every form change (INV-33)',
        );
      },
    );

    // ── Sub-property 10: Handler count completeness ─────────────────────
    Glados(any.intInRange(0, _appendOnlyHandlers.length - 1)).test(
      'append-only handler list is complete (6 handlers)',
      (index) {
        expect(
          _appendOnlyHandlers.length,
          equals(6),
          reason:
              'Must verify all 6 append-only handlers for INV-3 compliance. '
              'If a new handler is added, update this test.',
        );

        final spec = _appendOnlyHandlers[index];
        expect(spec.handlerFilePath, isNotEmpty);
        expect(spec.displayName, isNotEmpty);
        expect(spec.testFilePath, isNotEmpty);
        expect(spec.mechanismMarker, isNotEmpty);
        expect(spec.doubleExecutionMarker, isNotEmpty);
      },
    );
  });
}
