import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/admin_providers.dart';
import '../../../../application/admin/accept_invitation_command.dart';
import '../lock_screen.dart';

/// Public screen for accepting a pending invitation.
///
/// Reached via `/accept-invite?token=<token>` — no auth required to load.
/// The user must sign in (or sign up) before the token can be consumed.
///
/// Flow:
///   1. Screen loads → validates token via [PostgresInvitationQueryService].
///   2. If invalid/expired: shows error card.
///   3. If valid: shows invitation details + email/password form.
///   4. On submit: sign in (or sign up) → call [AcceptInvitationHandler].
///   5. On success: navigate to [AdminLockScreen] (which auto-redirects on session).
class AcceptInviteScreen extends ConsumerStatefulWidget {
  final String token;

  const AcceptInviteScreen({super.key, required this.token});

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // null = loading, true = valid, false = invalid
  bool? _tokenValid;
  String? _invitedRole;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _validateToken();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _validateToken() async {
    try {
      final invitation = await ref
          .read(invitationQueryServiceProvider)
          .findActiveByToken(widget.token);

      if (!mounted) return;

      if (invitation == null) {
        setState(() => _tokenValid = false);
      } else {
        setState(() {
          _tokenValid = true;
          _invitedRole = invitation.role.label;
          _emailController.text = invitation.email;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _tokenValid = false);
    }
  }

  Future<void> _accept() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;

      // Sign in (existing user) or sign up (new user)
      String userId;
      try {
        final res = await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        userId = res.user!.id;
      } on AuthException {
        // If sign-in fails, attempt sign-up (new user created by invitation)
        final res = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        userId = res.user!.id;
      }

      // Accept the invitation — provisions user_roles atomically
      await ref
          .read(acceptInvitationHandlerProvider)
          .handle(AcceptInvitationCommand(token: widget.token, userId: userId));

      // Refresh the session so the JWT hook re-runs with the now-populated
      // user_roles row — this injects organization_id + role into the token.
      await supabase.auth.refreshSession();

      if (!mounted) return;
      // Force clean URL redirect via browser API to clear '?token=...'
      if (kIsWeb) {
        web.window.location.replace('/');
      } else {
        unawaited(
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminLockScreen()),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('AuthException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: Card(
              color: VeraProbColors.surface,
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_tokenValid == null) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Verificando convite...'),
        ],
      );
    }

    if (_tokenValid == false) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cancel_outlined,
            color: VeraProbColors.error,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text('Convite Inválido', style: VeraProbTypography.sectionTitle),
          const SizedBox(height: 8),
          Text(
            'Este link de convite é inválido, expirou ou já foi utilizado.',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            color: VeraProbColors.primary,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Aceitar Convite',
            style: VeraProbTypography.sectionTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Você foi convidado como $_invitedRole.\nDefina sua senha para ativar o acesso.',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'E-mail'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha'),
            validator: (v) {
              if (v == null || v.length < 6) return 'Mínimo 6 caracteres.';
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: VeraProbColors.error, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _accept,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Ativar Acesso'),
          ),
        ],
      ),
    );
  }
}
