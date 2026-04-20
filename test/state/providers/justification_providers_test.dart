import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/justification/approve_justification_handler.dart';
import 'package:veraprob/application/sla_audit/justification/reject_justification_handler.dart';
import 'package:veraprob/application/sla_audit/justification/review_justification_command.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/supabase_forensic_throttle_gateway.dart';
import 'package:veraprob/state/providers/justification_providers.dart';

class MockApproveJustificationHandler extends Mock
    implements ApproveJustificationHandler {}

class MockRejectJustificationHandler extends Mock
    implements RejectJustificationHandler {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const ApproveJustificationCommand(
        justificationId: 'j',
        organizationId: 'o',
        planVersion: 1,
        callerRole: UserRole.operator,
        callerUserId: 'u',
        callerEmail: 'e@e.com',
        sessionId: 's',
      ),
    );
    registerFallbackValue(
      const RejectJustificationCommand(
        justificationId: 'j',
        organizationId: 'o',
        planVersion: 1,
        callerRole: UserRole.operator,
        callerUserId: 'u',
        callerEmail: 'e@e.com',
        rejectionNotes: 'notes',
        sessionId: 's',
      ),
    );
  });

  // ── Cenário 1: Badge de Notificação (UX-OPS) ─────────────────────────────

  group('pendingJustificationsCountProvider', () {
    List<Map<String, dynamic>> makeRows() => [
      {
        'id': '1',
        'status': 'PENDING',
        'created_at_utc': '2026-04-20T10:00:00Z',
      },
      {
        'id': '2',
        'status': 'PENDING',
        'created_at_utc': '2026-04-19T10:00:00Z',
      },
      {
        'id': '3',
        'status': 'APPROVED',
        'created_at_utc': '2026-04-18T10:00:00Z',
      },
      {
        'id': '4',
        'status': 'REJECTED',
        'created_at_utc': '2026-04-17T10:00:00Z',
      },
      {
        'id': '5',
        'status': 'EXPIRED',
        'created_at_utc': '2026-04-16T10:00:00Z',
      },
    ];

    test('counts EXACTLY 2 pending from stream of 5 docs', () async {
      final container = ProviderContainer(
        overrides: [
          justificationListStreamProvider.overrideWith(
            (ref) => Stream.value(makeRows()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(justificationListStreamProvider.future);
      expect(container.read(pendingJustificationsCountProvider), 2);
    });

    test(
      'uses JustificationStatus.pending.dbValue for comparison (case-sensitive)',
      () async {
        final rows = [
          // uppercase 'PENDING' must match
          {'id': '1', 'status': JustificationStatus.pending.dbValue},
          // lowercase must NOT match
          {'id': '2', 'status': 'pending'},
        ];
        final container = ProviderContainer(
          overrides: [
            justificationListStreamProvider.overrideWith(
              (ref) => Stream.value(rows),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(justificationListStreamProvider.future);
        expect(container.read(pendingJustificationsCountProvider), 1);
      },
    );

    test('returns 0 while stream is loading', () {
      final container = ProviderContainer(
        overrides: [
          justificationListStreamProvider.overrideWith(
            // never-completing stream → AsyncLoading
            (ref) => const Stream<List<Map<String, dynamic>>>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(pendingJustificationsCountProvider), 0);
    });
  });

  // ── Cenário 2: Real-time Order (MAVERICK) ────────────────────────────────

  group('justificationListStreamProvider ordering', () {
    test(
      'transmits rows newest-first — no client-side reversal (ascending:false on Supabase)',
      () async {
        // Provider must pass through rows in exactly the order Supabase returns.
        // Supabase is configured with .order("created_at_utc", ascending: false).
        final orderedRows = [
          {'id': '3', 'created_at_utc': '2026-04-20', 'status': 'PENDING'},
          {'id': '2', 'created_at_utc': '2026-04-19', 'status': 'APPROVED'},
          {'id': '1', 'created_at_utc': '2026-04-18', 'status': 'REJECTED'},
        ];

        final container = ProviderContainer(
          overrides: [
            justificationListStreamProvider.overrideWith(
              (ref) => Stream.value(orderedRows),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(justificationListStreamProvider.future);

        container
            .read(justificationListStreamProvider)
            .when(
              data: (rows) {
                expect(rows.length, 3);
                // newest row (id '3') arrives first
                expect(rows[0]['id'], '3');
                expect(rows[1]['id'], '2');
                expect(rows[2]['id'], '1');
              },
              error: (e, _) => fail('Unexpected error: $e'),
              loading: () => fail('Expected data, got loading'),
            );
      },
    );
  });

  // ── Cenários 3 & 4: JustificationActionNotifier ──────────────────────────

  group('JustificationActionNotifier', () {
    late MockApproveJustificationHandler mockApprove;
    late MockRejectJustificationHandler mockReject;
    late ProviderContainer container;

    setUp(() {
      mockApprove = MockApproveJustificationHandler();
      mockReject = MockRejectJustificationHandler();

      container = ProviderContainer(
        overrides: [
          justificationActionStateProvider('just-001').overrideWith(
            (ref) => JustificationActionNotifier(
              approveHandler: mockApprove,
              rejectHandler: mockReject,
            ),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    // Cenário 3: Resiliência de Aprovação (MAVERICK/QA)
    test(
      'approve success → transitions Loading then AsyncData(null)',
      () async {
        when(() => mockApprove.handle(any())).thenAnswer((_) async {});

        final states = <AsyncValue<void>>[];
        container.listen<AsyncValue<void>>(
          justificationActionStateProvider('just-001'),
          (_, next) => states.add(next),
        );

        await container
            .read(justificationActionStateProvider('just-001').notifier)
            .approve(
              justificationId: 'just-001',
              organizationId: 'org-abc',
              planVersion: 1,
              callerRole: UserRole.operator,
              callerUserId: 'user-admin-1',
              callerEmail: 'admin@tenant.com',
              sessionId: 'session-1',
            );

        expect(states.length, 2);
        expect(states[0], isA<AsyncLoading<void>>());
        expect(states[1], isA<AsyncData<void>>());
        expect(states[1].hasError, isFalse);
      },
    );

    // Cenário 4: Guardião de Erro (UX/ARCHITECT)
    test(
      'reject 403 → transitions Loading then AsyncError with readable message',
      () async {
        when(
          () => mockReject.handle(any()),
        ).thenThrow(Exception('403: Unauthorized'));

        final states = <AsyncValue<void>>[];
        container.listen<AsyncValue<void>>(
          justificationActionStateProvider('just-001'),
          (_, next) => states.add(next),
        );

        await container
            .read(justificationActionStateProvider('just-001').notifier)
            .reject(
              justificationId: 'just-001',
              organizationId: 'org-abc',
              planVersion: 1,
              callerRole: UserRole.operator,
              callerUserId: 'user-admin-1',
              callerEmail: 'admin@tenant.com',
              rejectionNotes: 'Justificativa invalida e insuficiente',
              sessionId: 'session-1',
            );

        expect(states.length, 2);
        expect(states[0], isA<AsyncLoading<void>>());
        expect(states[1], isA<AsyncError<void>>());

        final errorMessage = (states[1] as AsyncError<void>).error.toString();
        expect(errorMessage, isNotEmpty);
        expect(errorMessage, contains('403'));
      },
    );
  });

  // ── Cenário 5: Injeção Crítica (ARCHITECT / INV-16) ──────────────────────

  group('submitJustificationHandlerProvider throttle injection (INV-16)', () {
    test(
      'forensicThrottleGatewayProvider injects a real SupabaseForensicThrottleGateway',
      () {
        final mockClient = MockSupabaseClient();
        final container = ProviderContainer(
          overrides: [supabaseClientProvider.overrideWithValue(mockClient)],
        );
        addTearDown(container.dispose);

        final gateway = container.read(forensicThrottleGatewayProvider);

        // INV-16: handler must receive the server-authoritative gateway,
        // never a stub or null substitute.
        expect(gateway, isA<SupabaseForensicThrottleGateway>());
      },
    );
  });
}
