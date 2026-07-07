import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/telegram/generate_telegram_binding_token_command.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/telegram_providers.dart';

/// Dialog shown when an operator taps "Vincular Telegram" on a driver row.
///
/// Generates a 15-minute 8-char binding code. The driver types this code
/// into the VeraProb Telegram bot to link their chat_id to their profile.
class TelegramBindingDialog extends ConsumerStatefulWidget {
  final String driverId;
  final String driverName;
  final String organizationId;

  const TelegramBindingDialog({
    super.key,
    required this.driverId,
    required this.driverName,
    required this.organizationId,
  });

  @override
  ConsumerState<TelegramBindingDialog> createState() =>
      _TelegramBindingDialogState();

  /// INV-1: JWT org_id is the inviolable sovereignty anchor.
  /// Widget prop cannot be trusted alone — validate against JWT before any I/O.
  static void assertOrgIdMatch({
    required String widgetOrgId,
    required String? jwtOrgId,
  }) {
    if (widgetOrgId.isEmpty || jwtOrgId == null || jwtOrgId != widgetOrgId) {
      throw SovereigntyViolationException(
        payloadOrgId: widgetOrgId,
        jwtOrgId: jwtOrgId ?? 'none',
      );
    }
  }
}

class _TelegramBindingDialogState extends ConsumerState<TelegramBindingDialog> {
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _codeCopied = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(DateTime expiresAtUtc) {
    _countdownTimer?.cancel();
    _tick(expiresAtUtc);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick(expiresAtUtc);
    });
  }

  void _tick(DateTime expiresAtUtc) {
    final now = DateTime.now().toUtc();
    final diff = expiresAtUtc.difference(now);
    if (mounted) {
      setState(() {
        _remaining = diff.isNegative ? Duration.zero : diff;
      });
      if (diff.isNegative) _countdownTimer?.cancel();
    }
  }

  Future<void> _generate() async {
    // INV-1: Fail-Fast sovereignty check before any RPC call.
    final jwtOrgId = ref.read(currentOrganizationIdProvider);
    try {
      TelegramBindingDialog.assertOrgIdMatch(
        widgetOrgId: widget.organizationId,
        jwtOrgId: jwtOrgId,
      );
    } on SovereigntyViolationException catch (e) {
      LoggerService().error(
        'SovereigntyViolation in TelegramBindingDialog',
        error: e,
      );
      ref
          .read(telegramBindingNotifierProvider(widget.driverId).notifier)
          .fail(e, StackTrace.current);
      return;
    }

    final userId = ref.read(currentOperatorIdProvider);
    final role = ref.read(currentUserRoleProvider);
    final sessionId =
        ref.read(authStateProvider).value?.session?.accessToken ?? '';

    if (userId == null) return;

    await ref
        .read(telegramBindingNotifierProvider(widget.driverId).notifier)
        .generateToken(
          GenerateTelegramBindingTokenCommand(
            organizationId: widget.organizationId,
            driverId: widget.driverId,
            callerRole: role,
            callerUserId: userId,
            sessionId: sessionId,
          ),
        );

    final tokenState = ref.read(
      telegramBindingNotifierProvider(widget.driverId),
    );
    if (tokenState case AsyncData(:final value)) {
      if (value != null) _startCountdown(value.expiresAtUtc);
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _codeCopied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _codeCopied = false);
    });
  }

  String _formatCountdown(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  @override
  Widget build(BuildContext context) {
    final tokenState = ref.watch(
      telegramBindingNotifierProvider(widget.driverId),
    );
    final bindingAsync = ref.watch(
      driverHasActiveTelegramBindingProvider((
        driverId: widget.driverId,
        organizationId: widget.organizationId,
      )),
    );
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: VeraProbRadii.xlAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: VeraProbColors.primary.withValues(alpha: 0.1),
                      borderRadius: VeraProbRadii.lgAll,
                    ),
                    child: const Icon(
                      Icons.telegram,
                      color: VeraProbColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vincular Telegram',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.driverName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: VeraProbColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Active binding warning
              bindingAsync is AsyncData<bool> && bindingAsync.value == true
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: VeraProbColors.warning.withValues(alpha: 0.1),
                        borderRadius: VeraProbRadii.lgAll,
                        border: Border.all(
                          color: VeraProbColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: VeraProbColors.warning,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Este motorista já possui vinculação ativa. '
                              'Gerar novo código irá desvincular o chat anterior.',
                              style: TextStyle(
                                fontSize: 12,
                                color: VeraProbColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),

              // Instructions
              switch (tokenState) {
                AsyncData(:final value) =>
                  value == null
                      ? _buildInstructions()
                      : _remaining == Duration.zero
                      ? _buildExpiredState()
                      : _buildCodeDisplay(value, colorScheme),
                AsyncLoading() => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                AsyncError() => _buildErrorState(),
              },

              const SizedBox(height: 20),

              // Action button
              SizedBox(
                width: double.infinity,
                child: switch (tokenState) {
                  AsyncData(:final value) => FilledButton.icon(
                    onPressed: tokenState.isLoading ? null : _generate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(value == null ? 'Gerar Código' : 'Novo Código'),
                    style: FilledButton.styleFrom(
                      backgroundColor: VeraProbColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  AsyncLoading() => FilledButton(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  AsyncError() => FilledButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Tentar Novamente'),
                    style: FilledButton.styleFrom(
                      backgroundColor: VeraProbColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Como vincular:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: VeraProbColors.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        _Step(number: '1', text: 'Gere o código abaixo'),
        _Step(
          number: '2',
          text: 'Peça ao motorista para abrir o bot @VeraProbBot no Telegram',
        ),
        _Step(
          number: '3',
          text: 'O motorista envia o código de 8 caracteres no chat',
        ),
        _Step(
          number: '4',
          text: 'Vinculação confirmada — evidências podem ser enviadas',
        ),
        SizedBox(height: 4),
        Text(
          'O código expira em 15 minutos.',
          style: TextStyle(fontSize: 12, color: VeraProbColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildCodeDisplay(
    TelegramBindingToken token,
    ColorScheme colorScheme,
  ) {
    final isExpiringSoon = _remaining.inSeconds < 60;

    return Column(
      children: [
        // Code box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: VeraProbColors.surfaceElevated,
            borderRadius: VeraProbRadii.lgAll,
            border: Border.all(
              color: isExpiringSoon
                  ? VeraProbColors.warning
                  : VeraProbColors.primary.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              const Text(
                'CÓDIGO DE VINCULAÇÃO',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: VeraProbColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                token.code,
                style: VeraProbTypography.mono(
                  size: 36,
                  weight: FontWeight.w800,
                  letterSpacing: 8,
                  color: isExpiringSoon
                      ? VeraProbColors.warning
                      : VeraProbColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: isExpiringSoon
                        ? VeraProbColors.warning
                        : VeraProbColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Expira em ${_formatCountdown(_remaining)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isExpiringSoon
                          ? VeraProbColors.warning
                          : VeraProbColors.textSecondary,
                      fontWeight: isExpiringSoon
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Copy button
        OutlinedButton.icon(
          onPressed: () => _copyCode(token.code),
          icon: Icon(_codeCopied ? Icons.check : Icons.copy, size: 16),
          label: Text(_codeCopied ? 'Copiado!' : 'Copiar código'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _codeCopied ? VeraProbColors.success : null,
          ),
        ),
      ],
    );
  }

  Widget _buildExpiredState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VeraProbColors.error.withValues(alpha: 0.1),
        borderRadius: VeraProbRadii.lgAll,
        border: Border.all(color: VeraProbColors.error.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.timer_off, size: 18, color: VeraProbColors.error),
          SizedBox(width: 8),
          Text(
            'Código expirado. Gere um novo.',
            style: TextStyle(fontSize: 13, color: VeraProbColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.error.withValues(alpha: 0.1),
        borderRadius: VeraProbRadii.lgAll,
        border: Border.all(color: VeraProbColors.error.withValues(alpha: 0.3)),
      ),
      child: const Text(
        'Falha ao processar vínculo Telegram. Tente novamente.',
        style: TextStyle(fontSize: 12, color: VeraProbColors.error),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: VeraProbColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: VeraProbColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
