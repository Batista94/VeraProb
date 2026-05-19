import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/mfa_providers.dart';
import 'package:veraprob/features/admin/presentation/lock_screen.dart';
import 'package:veraprob/features/super_admin/presentation/super_admin_shell.dart';
import 'package:veraprob/features/super_admin/presentation/screens/mfa_challenge_screen.dart';

/// TOTP enrollment screen for SuperAdmin (INV-6).
///
/// Three phases:
/// 1. QR code display + manual secret
/// 2. 6-digit confirmation to validate enrollment works
/// 3. Recovery codes display with mandatory acknowledgment
class MfaEnrollmentScreen extends ConsumerStatefulWidget {
  const MfaEnrollmentScreen({super.key});

  @override
  ConsumerState<MfaEnrollmentScreen> createState() =>
      _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends ConsumerState<MfaEnrollmentScreen> {
  MfaEnrollmentResult? _enrollResult;
  bool _isLoading = true;
  String? _error;

  // Phase tracking
  bool _enrollmentComplete = false;
  bool _codesAcknowledged = false;

  // Confirmation code input
  final _codeController = TextEditingController();
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startEnrollment());
  }

  Future<void> _startEnrollment() async {
    try {
      final handler = ref.read(mfaEnrollmentHandlerProvider);
      final result = await handler.handle();
      if (mounted) {
        setState(() {
          _enrollResult = result;
          _isLoading = false;
        });
      }
    } on MfaException catch (e) {
      if (e.isNotEnabled && kDebugMode) {
        if (!mounted) return;
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const SuperAdminShell()),
          (_) => false,
        );
        return;
      }
      rethrow;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmEnrollment() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;

    setState(() => _isVerifying = true);

    try {
      final handler = ref.read(mfaChallengeHandlerProvider);
      final challengeResult = await ref
          .read(mfaRepositoryProvider)
          .createChallenge(_enrollResult!.factorId);

      final result = await handler.verify(
        factorId: _enrollResult!.factorId,
        challengeId: challengeResult.challengeId,
        code: code,
      );

      if (!mounted) return;

      switch (result) {
        case MfaVerificationSuccess():
          setState(() {
            _enrollmentComplete = true;
            _isVerifying = false;
          });
        case MfaVerificationFailure():
          setState(() {
            _error = result.message;
            _isVerifying = false;
            _codeController.clear();
          });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _navigateToShell() async {
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MfaChallengeScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Configurando autenticação multifator...',
            style: TextStyle(color: VeraProbColors.textSecondary),
          ),
        ],
      );
    }

    if (_error != null && _enrollResult == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async =>
                await Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminLockScreen(),
                  ),
                  (_) => false,
                ),
            child: const Text('Voltar ao Login'),
          ),
        ],
      );
    }

    if (_enrollmentComplete) {
      return _buildRecoveryCodes();
    }

    return _buildQrAndConfirmation();
  }

  Widget _buildQrAndConfirmation() {
    final result = _enrollResult!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: VeraProbColors.superAdminSurface.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.security,
            size: 40,
            color: VeraProbColors.superAdminSurface,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Configurar Autenticação MFA',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: VeraProbColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Escaneie o QR code com seu aplicativo autenticador\n(Google Authenticator, Authy, etc.)',
          textAlign: TextAlign.center,
          style: TextStyle(color: VeraProbColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // QR Code
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: result.totpUri,
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),

        // Manual secret
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: VeraProbColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VeraProbColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SelectableText(
                  result.secret,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: VeraProbColors.textPrimary,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copiar código',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result.secret));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Código copiado'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Confirmation input
        const Text(
          'Confirme o código gerado pelo aplicativo:',
          style: TextStyle(
            color: VeraProbColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 200,
          child: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofocus: true,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 8,
              fontFamily: 'monospace',
              color: VeraProbColors.textPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              errorText: _error,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) {
              if (_error != null) setState(() => _error = null);
              if (value.length == 6) unawaited(_confirmEnrollment());
            },
          ),
        ),
        const SizedBox(height: 16),
        if (_isVerifying) const CircularProgressIndicator(),
      ],
    );
  }

  Widget _buildRecoveryCodes() {
    final codes = _enrollResult!.recoveryCodes;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 48),
        const SizedBox(height: 16),
        const Text(
          'MFA Configurado com Sucesso',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: VeraProbColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Salve seus códigos de recuperação em local seguro.\nEles não serão exibidos novamente.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.amber, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // Recovery codes grid
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VeraProbColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VeraProbColors.border),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: codes
                .map(
                  (code) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: VeraProbColors.background,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: VeraProbColors.textPrimary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Copy all button
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: codes.join('\n')));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Códigos copiados'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar Todos'),
        ),
        const SizedBox(height: 24),

        // Acknowledgment checkbox
        CheckboxListTile(
          value: _codesAcknowledged,
          onChanged: (v) => setState(() => _codesAcknowledged = v ?? false),
          title: const Text(
            'Salvei meus códigos de recuperação em local seguro.',
            style: TextStyle(color: VeraProbColors.textPrimary, fontSize: 13),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _codesAcknowledged ? _navigateToShell : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: VeraProbColors.superAdminSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'CONTINUAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
