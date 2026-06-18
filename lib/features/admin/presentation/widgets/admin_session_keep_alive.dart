import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Wraps the Admin shell to keep the Supabase session alive and monitor
/// for user inactivity.
///
/// Two responsibilities:
/// 1. **Proactive Token Refresh** — refreshes the JWT every [_refreshInterval]
///    (well before the 60-min Supabase expiry) to prevent silent token death
///    in Flutter Web WASM where the SDK auto-refresh can be unreliable.
/// 2. **Idle Detection** — shows a warning dialog after [_idleWarningDuration]
///    of no pointer activity, then force-logs out after [_forceLogoutDuration].
///
/// Mirrors the behavior of [SuperAdminSessionTimeout] with longer timeouts
/// suited for admin operational workflows (CSV imports, contract setup, etc.).
class AdminSessionKeepAlive extends ConsumerStatefulWidget {
  final Widget child;

  const AdminSessionKeepAlive({super.key, required this.child});

  @override
  ConsumerState<AdminSessionKeepAlive> createState() =>
      _AdminSessionKeepAliveState();
}

class _AdminSessionKeepAliveState extends ConsumerState<AdminSessionKeepAlive> {
  Timer? _refreshTimer;
  Timer? _idleTimer;
  Timer? _logoutTimer;
  bool _isWarningOpen = false;

  /// Refresh the JWT token every 50 minutes (JWT expires at 60 min).
  static const _refreshInterval = Duration(minutes: 50);

  /// Show idle warning after 25 minutes of no pointer activity.
  static const _idleWarningDuration = Duration(minutes: 25);

  /// Force logout after 30 minutes of no pointer activity.
  static const _forceLogoutDuration = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
    _resetIdleTimers();
  }

  // ── Proactive Token Refresh ──────────────────────────────────────────────

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshSession());
  }

  Future<void> _refreshSession() async {
    try {
      await ref.read(authRepositoryProvider).refreshSession();
    } catch (_) {
      // If refresh fails, the router's auth redirect will bounce to /login
      // on the next auth state change event.
    }
  }

  // ── Idle Detection ───────────────────────────────────────────────────────

  void _handleUserInteraction() {
    if (_isWarningOpen) return;
    _resetIdleTimers();
  }

  void _resetIdleTimers() {
    _idleTimer?.cancel();
    _logoutTimer?.cancel();

    _idleTimer = Timer(_idleWarningDuration, _showWarning);
    _logoutTimer = Timer(_forceLogoutDuration, _forceLogout);
  }

  void _showWarning() {
    if (!mounted) return;
    setState(() => _isWarningOpen = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Aviso de Inatividade'),
        content: const Text(
          'Por motivos de segurança, sua sessão será encerrada em breve '
          'por inatividade.\n\nDeseja continuar logado?',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) {
                setState(() => _isWarningOpen = false);
                _resetIdleTimers();
                // Also proactively refresh when user confirms they're active
                _refreshSession();
              }
            },
            child: const Text('Continuar Logado'),
          ),
        ],
      ),
    );
  }

  Future<void> _forceLogout() async {
    _refreshTimer?.cancel();
    _idleTimer?.cancel();
    _logoutTimer?.cancel();

    if (_isWarningOpen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {}

    if (mounted) {
      context.go(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _idleTimer?.cancel();
    _logoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _handleUserInteraction(),
      onPointerMove: (_) => _handleUserInteraction(),
      onPointerUp: (_) => _handleUserInteraction(),
      child: widget.child,
    );
  }
}
