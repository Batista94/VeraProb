import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../infrastructure/providers/supabase_provider.dart';
import '../providers/local_fact_queue_providers.dart';

/// Connection lifecycle states for the Edge Ledger sync.
enum EdgeLedgerConnectionState { connected, disconnected, syncing }

/// Watches Supabase auth events to detect connectivity restoration.
///
/// On [AuthChangeEvent.tokenRefreshed] (which fires when the client
/// reconnects after an outage), triggers [LocalSyncOrchestrator.onConnectionRestored]
/// to fill any sequence gaps in the local fact queue.
///
/// **INV-23:** OCC read-only — this notifier never mutates server state.
class ConnectivityNotifier
    extends AutoDisposeNotifier<EdgeLedgerConnectionState> {
  StreamSubscription<AuthState>? _authSub;

  @override
  EdgeLedgerConnectionState build() {
    final supabase = ref.watch(supabaseClientProvider);
    _authSub?.cancel();

    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.tokenRefreshed ||
          data.event == AuthChangeEvent.signedIn) {
        _onReconnected(data.session);
      } else if (data.event == AuthChangeEvent.signedOut) {
        state = EdgeLedgerConnectionState.disconnected;
      }
    });

    ref.onDispose(() => _authSub?.cancel());
    return EdgeLedgerConnectionState.connected;
  }

  void _onReconnected(Session? session) {
    final organizationId =
        session?.user.userMetadata?['organization_id'] as String?;
    if (organizationId == null) return;

    state = EdgeLedgerConnectionState.syncing;

    final orchestrator = ref.read(localSyncOrchestratorProvider);
    orchestrator
        .onConnectionRestored(
          organizationId: organizationId,
          missingFacts: const [],
        )
        .then((_) => state = EdgeLedgerConnectionState.connected)
        .catchError((_) => state = EdgeLedgerConnectionState.connected);
  }
}
