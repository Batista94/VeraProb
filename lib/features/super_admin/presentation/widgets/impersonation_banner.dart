import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/start_impersonation_handler.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

const Color _kImpersonationBannerColor = Color(0xFFB00020);
const TextStyle _kImpersonationTextStyle = TextStyle(
  color: Colors.white,
  fontFamily: 'monospace',
  fontWeight: FontWeight.bold,
  fontSize: 13,
);
const TextStyle _kImpersonationTimerStyle = TextStyle(
  color: Colors.white,
  fontFamily: 'monospace',
  fontWeight: FontWeight.bold,
  fontSize: 14,
);
const TextStyle _kImpersonationButtonTextStyle = TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 12,
);

/// Persistent, inescapable banner displayed during impersonation sessions.
///
/// Security requirements:
/// - Cannot be minimized, closed, or hidden
/// - Always first child in the layout (never inside a scrollable)
/// - Red solid background (#B00020) for maximum visibility
/// - Shows countdown timer and "Encerrar Sessão" button
class ImpersonationBanner extends ConsumerStatefulWidget {
  final ImpersonationSessionInfo session;
  final VoidCallback onSessionEnded;

  const ImpersonationBanner({
    super.key,
    required this.session,
    required this.onSessionEnded,
  });

  @override
  ConsumerState<ImpersonationBanner> createState() =>
      _ImpersonationBannerState();
}

class _ImpersonationBannerState extends ConsumerState<ImpersonationBanner> {
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _isRevoking = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.session.remainingDuration;
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tick(),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _tick() {
    final remaining = widget.session.remainingDuration;
    if (remaining == Duration.zero) {
      _countdownTimer?.cancel();
      widget.onSessionEnded();
      return;
    }
    setState(() => _remaining = remaining);
  }

  Future<void> _revokeSession() async {
    if (_isRevoking) return;
    setState(() => _isRevoking = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final handler = ref.read(revokeImpersonationHandlerProvider);
      await handler.handle(
        impersonationSessionId: widget.session.sessionId,
        targetOrgId: widget.session.targetOrgId,
        callerSessionId: widget.session.sessionId,
        reason: 'Manual revocation by super_admin',
      );
      widget.onSessionEnded();
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e is DomainException
          ? e.message
          : 'Falha ao encerrar sessão.';
      messenger.showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: VeraProbColors.error,
        ),
      );
      setState(() => _isRevoking = false);
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: _kImpersonationBannerColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.visibility, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'MODO IMPERSONATION — Atuando como: ${widget.session.targetOrgName}',
              style: _kImpersonationTextStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatDuration(_remaining),
              style: _kImpersonationTimerStyle,
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _isRevoking ? null : _revokeSession,
            icon: _isRevoking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.stop_circle_outlined, size: 16),
            label: const Text('Encerrar Sessão'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: _kImpersonationButtonTextStyle,
            ),
          ),
        ],
      ),
    );
  }
}
