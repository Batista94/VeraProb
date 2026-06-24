import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Wraps the SuperAdmin shell to monitor for user inactivity.
/// Shows a warning dialog after 5 minutes of idle time.
/// Forces logout after 7 minutes of idle time.
/// Proactively refreshes the JWT every 50 minutes to prevent silent expiry.
class SuperAdminSessionTimeout extends ConsumerStatefulWidget {
  final Widget child;

  const SuperAdminSessionTimeout({super.key, required this.child});

  @override
  ConsumerState<SuperAdminSessionTimeout> createState() =>
      _SuperAdminSessionTimeoutState();
}

class _SuperAdminSessionTimeoutState
    extends ConsumerState<SuperAdminSessionTimeout> {
  Timer? _idleTimer;
  Timer? _logoutTimer;
  Timer? _refreshTimer;
  bool _isWarningOpen = false;

  /// Refresh the JWT token every 50 minutes (JWT expires at 60 min).
  static const _refreshInterval = Duration(minutes: 50);

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
    _resetTimers();
  }

  void _handleUserInteraction() {
    if (_isWarningOpen) return;
    _resetTimers();
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
    }
  }

  // ── Idle Detection ───────────────────────────────────────────────────────

  void _resetTimers() {
    _idleTimer?.cancel();
    _logoutTimer?.cancel();

    _idleTimer = Timer(const Duration(minutes: 5), _showWarning);
    _logoutTimer = Timer(const Duration(minutes: 7), _forceLogout);
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
          'Por motivos de segurança, sua sessão será encerrada em breve por inatividade.\n\nDeseja continuar logado?',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) {
                setState(() => _isWarningOpen = false);
                _resetTimers();
                // Proactively refresh when user confirms they're active
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
    _idleTimer?.cancel();
    _logoutTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _handleUserInteraction(),
      onPointerMove: (_) {
        // Debounce or just keep resetting. Timer cancel/recreation is cheap enough in Dart,
        // but pointerMove fires constantly. Just calling _handleUserInteraction is fine.
        _handleUserInteraction();
      },
      onPointerUp: (_) => _handleUserInteraction(),
      child: widget.child,
    );
  }
}
