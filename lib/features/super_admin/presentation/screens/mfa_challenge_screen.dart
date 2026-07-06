import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/mfa_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

const _kScreenTitle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.bold,
  color: VeraProbColors.textPrimary,
);
const _kSubtitle = TextStyle(color: VeraProbColors.textSecondary, fontSize: 13);
const _kLoadingCaption = TextStyle(color: VeraProbColors.textSecondary);
TextStyle get _kOtpField => VeraProbTypography.mono(
  size: 28,
  letterSpacing: 8,
  color: VeraProbColors.textPrimary,
);
const _kErrorBody = TextStyle(color: VeraProbColors.error, fontSize: 13);
const _kAttemptsWarning = TextStyle(
  color: VeraProbColors.warning,
  fontSize: 12,
);
const _kBackLinkText = TextStyle(color: VeraProbColors.textSecondary);

/// TOTP challenge screen for SuperAdmin login (INV-6).
///
/// Displays a 6-digit input, auto-submits, shows lockout countdown.
class MfaChallengeScreen extends ConsumerStatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  ConsumerState<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends ConsumerState<MfaChallengeScreen> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  String? _error;
  int _remainingAttempts = 5;

  // Lockout state
  bool _isLockedOut = false;
  DateTime? _lockedUntil;
  Timer? _lockoutTimer;

  // Challenge state
  String? _challengeId;
  String? _factorId;
  bool _isLoadingChallenge = true;

  @override
  void initState() {
    super.initState();
    _createChallenge();
  }

  Future<void> _createChallenge() async {
    try {
      final handler = ref.read(mfaChallengeHandlerProvider);
      final result = await handler.createChallenge();
      if (mounted) {
        setState(() {
          _challengeId = result.challengeId;
          _factorId = result.factorId;
          _isLoadingChallenge = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is DomainException
              ? e.message
              : 'Falha ao iniciar o desafio MFA.';
          _isLoadingChallenge = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || _challengeId == null || _factorId == null) return;

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final handler = ref.read(mfaChallengeHandlerProvider);
      final result = await handler.verify(
        factorId: _factorId!,
        challengeId: _challengeId!,
        code: code,
      );

      if (!mounted) return;

      switch (result) {
        case MfaVerificationSuccess():
          context.go(AppRoutes.superAdminTenants);
        case MfaVerificationFailure():
          setState(() {
            _isVerifying = false;
            _error = result.message;
            _remainingAttempts = 5 - result.failedAttempts;
            _codeController.clear();
          });

          if (result.isLockedOut) {
            _startLockoutTimer(result.lockedUntil);
          } else {
            // Create a new challenge for the next attempt
            await _createChallenge();
          }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _error = e is DomainException
              ? e.message
              : 'Falha na validação do código MFA.';
        });
      }
    }
  }

  void _startLockoutTimer(DateTime? until) {
    _lockedUntil = until;
    setState(() => _isLockedOut = true);

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _lockoutTimer?.cancel();
        return;
      }

      final now = ref.read(dateTimeProviderProvider).nowUtc();
      if (_lockedUntil != null && now.isAfter(_lockedUntil!)) {
        _lockoutTimer?.cancel();
        setState(() {
          _isLockedOut = false;
          _lockedUntil = null;
          _remainingAttempts = 5;
          _error = null;
        });
        _createChallenge();
      } else {
        setState(() {}); // Refresh countdown
      }
    });
  }

  void _signOutAndReturn() {
    ref.read(authRepositoryProvider).signOut();
    context.go(AppRoutes.login);
  }

  String _formatCountdown() {
    if (_lockedUntil == null) return '';
    final now = ref.read(dateTimeProviderProvider).nowUtc();
    final diff = _lockedUntil!.difference(now);
    if (diff.isNegative) return '';
    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _codeController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final bool showAttemptWarning =
        !_isLockedOut && _remainingAttempts > 0 && _remainingAttempts < 5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: VeraProbColors.superAdminSurface.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isLockedOut ? Icons.lock_clock : Icons.verified_user,
            size: 40,
            color: _isLockedOut
                ? VeraProbColors.warning
                : VeraProbColors.superAdminSurface,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isLockedOut ? 'Conta Temporariamente Bloqueada' : 'Verificação MFA',
          style: _kScreenTitle,
        ),
        const SizedBox(height: 8),
        Text(
          _isLockedOut
              ? 'Tente novamente em ${_formatCountdown()}'
              : 'Digite o código do seu aplicativo autenticador',
          textAlign: TextAlign.center,
          style: _kSubtitle,
        ),
        const SizedBox(height: 32),

        if (_isLoadingChallenge) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Preparando desafio...', style: _kLoadingCaption),
        ] else ...[
          // Code input
          SizedBox(
            width: 200,
            child: TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              autofocus: true,
              enabled: !_isLockedOut && !_isVerifying,
              style: _kOtpField,
              decoration: const InputDecoration(
                counterText: '',
                hintText: '000000',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) {
                if (_error != null) setState(() => _error = null);
                if (value.length == 6) _verifyCode();
              },
            ),
          ),
        ],

        if (_isVerifying) ...[
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ],

        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: _kErrorBody, textAlign: TextAlign.center),
        ],

        if (showAttemptWarning) ...[
          const SizedBox(height: 8),
          Text(
            '$_remainingAttempts de 5 tentativas restantes',
            style: _kAttemptsWarning,
          ),
        ],

        const SizedBox(height: 32),
        TextButton(
          onPressed: _signOutAndReturn,
          child: const Text('Voltar ao Login', style: _kBackLinkText),
        ),
      ],
    );
  }
}
