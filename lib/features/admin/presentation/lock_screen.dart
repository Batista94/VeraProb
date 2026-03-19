import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/logger_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'admin_home.dart';

class AdminLockScreen extends StatefulWidget {
  const AdminLockScreen({super.key});

  @override
  State<AdminLockScreen> createState() => _AdminLockScreenState();
}

class _AdminLockScreenState extends State<AdminLockScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _supabase = Supabase.instance.client;

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-login if session already exists
    _supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final session = data.session;
      if (session != null) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const AdminHome()));
      }
    });
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Preencha E-mail e Senha');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      LoggerService().security('Admin Access Granted via Supabase: $email');
      // Navigation is handled by onAuthStateChange listener
    } on AuthException catch (e) {
      LoggerService().security('Admin Access Failed: ${e.message}');
      setState(() => _error = 'Credenciais Incorretas');
    } catch (e) {
      setState(() => _error = 'Erro interno inesperado');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: VeraProbColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: VeraProbColors.border),
            boxShadow: [
              BoxShadow(
                blurRadius: 40,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VeraProbColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 48,
                  color: VeraProbColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Autenticação Corporativa',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: VeraProbColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Plataforma de Auditoria SLA',
                style: TextStyle(
                  color: VeraProbColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: VeraProbColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'E-mail Corporativo',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(
                  color: VeraProbColors.textPrimary,
                  letterSpacing: 4,
                ),
                decoration: InputDecoration(
                  labelText: 'Senha de Acesso',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _error,
                ),
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VeraProbColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'ACESSAR SISTEMA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
