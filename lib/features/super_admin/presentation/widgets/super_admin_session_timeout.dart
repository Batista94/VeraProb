import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../admin/presentation/lock_screen.dart';

/// Wraps the SuperAdmin shell to monitor for user inactivity.
/// Shows a warning dialog after 5 minutes of idle time.
/// Forces logout after 7 minutes of idle time.
class SuperAdminSessionTimeout extends StatefulWidget {
  final Widget child;

  const SuperAdminSessionTimeout({super.key, required this.child});

  @override
  State<SuperAdminSessionTimeout> createState() => _SuperAdminSessionTimeoutState();
}

class _SuperAdminSessionTimeoutState extends State<SuperAdminSessionTimeout> {
  Timer? _idleTimer;
  Timer? _logoutTimer;
  bool _isWarningOpen = false;

  @override
  void initState() {
    super.initState();
    _resetTimers();
  }

  void _handleUserInteraction() {
    if (_isWarningOpen) return;
    _resetTimers();
  }

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
              }
            },
            child: const Text('Continuar Logado'),
          ),
        ],
      ),
    );
  }

  Future<void> _forceLogout() async {
    _idleTimer?.cancel();
    _logoutTimer?.cancel();

    if (_isWarningOpen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    if (mounted) {
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AdminLockScreen()),
        (_) => false,
      );
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _logoutTimer?.cancel();
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
