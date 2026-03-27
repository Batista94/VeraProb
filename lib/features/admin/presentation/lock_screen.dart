import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/logger_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/jwt_utils.dart';
import '../../../../infrastructure/super_admin/supabase_mfa_repository.dart';
import '../../super_admin/presentation/screens/mfa_challenge_screen.dart';
import '../../super_admin/presentation/screens/mfa_enrollment_screen.dart';
import '../../super_admin/presentation/super_admin_shell.dart';
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
        _routeAfterAuth(session);
      }
    });
  }

  /// Routes to the appropriate screen based on JWT claims and MFA status.
  ///
  /// For SuperAdmin users (INV-6):
  ///   - No TOTP enrolled → MfaEnrollmentScreen
  ///   - TOTP enrolled but AAL1 → MfaChallengeScreen
  ///   - AAL2 verified → SuperAdminShell
  ///
  /// Regular tenant users → AdminHome (unchanged).
  Future<void> _routeAfterAuth(Session session) async {
    final claims = decodeJwtPayload(session.accessToken);
    final appMeta = claims['app_metadata'] as Map<String, dynamic>?;
    final raw = appMeta?['super_admin'];

    if (kDebugMode) {
      debugPrint('[AUTH] JWT app_metadata: $appMeta');
      debugPrint('[AUTH] super_admin=$raw (${raw.runtimeType})');
    }

    final isSuperAdmin = raw == true || raw?.toString() == 'true';

    if (!isSuperAdmin) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminHome()),
      );
      return;
    }

    // SuperAdmin path: check MFA status to determine destination.
    try {
      final mfaRepo = SupabaseMfaRepository(_supabase);
      final mfaStatus = await mfaRepo.getMfaStatus();

      if (!mounted) return;

      final Widget destination;
      if (mfaStatus.needsEnrollment) {
        destination = const MfaEnrollmentScreen();
      } else if (mfaStatus.needsChallenge) {
        destination = const MfaChallengeScreen();
      } else {
        destination = const SuperAdminShell();
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AUTH] MFA status check failed: $e');
      }
      // Fallback: send to challenge screen (safe default).
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MfaChallengeScreen()),
      );
    }
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
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      LoggerService().security('Admin Access Granted via Supabase: $email');
      // Navigation handled by onAuthStateChange listener, but also route directly
      // in case the listener fires before the widget re-renders.
      if (mounted && response.session != null) {
        _routeAfterAuth(response.session!);
      }
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

  // ── Visual layer ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 768;

          if (!isDesktop) {
            // Mobile: only the login panel, 100% width — no ambient noise.
            return _buildLoginPanel(fullScreen: true);
          }

          // Desktop: 40 / 60 enterprise split.
          return Row(
            children: [
              SizedBox(
                width: constraints.maxWidth * 0.4,
                child: _buildLoginPanel(fullScreen: false),
              ),
              const Expanded(child: _ForensicAmbientPanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginPanel({required bool fullScreen}) {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        border: Border(
          right: fullScreen
              ? BorderSide.none
              : const BorderSide(color: VeraProbColors.border),
        ),
      ),
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: VeraProbColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 40,
                      color: VeraProbColors.primary,
                    ),
                  ),
                  const SizedBox(height: 28),
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
                  const SizedBox(height: 36),
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
        ),
      ),
    );
  }
}

// ── Right panel — Forensic Ambient (visual-only, no logic) ────────────────

class _ForensicAmbientPanel extends StatelessWidget {
  // Mock telemetry rows displayed as ambient text.
  static const List<_TelemetryRow> _rows = [
    _TelemetryRow('VH-0392', 'SLA_BREACH', '-23.5505, -46.6333', 'GUILTY'),
    _TelemetryRow('VH-1147', 'ON_ROUTE', '-22.9068, -43.1729', 'COMPLIANT'),
    _TelemetryRow('VH-0781', 'IDLE_EXCESS', '-19.9167, -43.9345', 'PENDING'),
    _TelemetryRow('VH-2240', 'SPEEDING', '-15.7942, -47.8822', 'GUILTY'),
    _TelemetryRow('VH-0055', 'MAINTENANCE', '-30.0277, -51.2287', 'INHIBITED'),
    _TelemetryRow('VH-1892', 'ON_ROUTE', '-3.7172, -38.5431', 'COMPLIANT'),
    _TelemetryRow('VH-0314', 'SLA_BREACH', '-12.9714, -38.5014', 'GUILTY'),
    _TelemetryRow('VH-0670', 'IDLE_EXCESS', '-8.0476, -34.877', 'PENDING'),
  ];

  const _ForensicAmbientPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base background.
        const ColoredBox(color: Color(0xFF080C10)),

        // Abstract node graph.
        const CustomPaint(painter: _NodeGraphPainter()),

        // Blurred telemetry feed overlay.
        ImageFiltered(
          imageFilter: const ColorFilter.mode(
            Color(0x55080C10),
            BlendMode.srcOver,
          ),
          child: _buildTelemetryFeed(),
        ),

        // Bottom gradient fade to black.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 200,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF080C10).withValues(alpha: 0.95),
                ],
              ),
            ),
          ),
        ),

        // Center brand badge.
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.gavel_rounded,
                size: 64,
                color: VeraProbColors.primary.withValues(alpha: 0.18),
              ),
              const SizedBox(height: 16),
              Text(
                'FORENSIC COMMAND CENTER',
                style: TextStyle(
                  color: VeraProbColors.primary.withValues(alpha: 0.22),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Telemetria · Veredicto · Ledger Imutável',
                style: TextStyle(
                  color: VeraProbColors.textSecondary.withValues(alpha: 0.25),
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryFeed() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _TelemetryRowWidget(row: r),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TelemetryRow {
  final String vehicleId;
  final String event;
  final String coords;
  final String verdict;

  const _TelemetryRow(this.vehicleId, this.event, this.coords, this.verdict);
}

class _TelemetryRowWidget extends StatelessWidget {
  final _TelemetryRow row;

  const _TelemetryRowWidget({required this.row});

  Color _verdictColor() => switch (row.verdict) {
    'GUILTY' => const Color(0xFFEF4444),
    'COMPLIANT' => const Color(0xFF22C55E),
    'INHIBITED' => const Color(0xFFF59E0B),
    _ => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            row.vehicleId,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
        SizedBox(
          width: 120,
          child: Text(
            row.event,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: Text(
            row.coords,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _verdictColor().withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _verdictColor().withValues(alpha: 0.3)),
          ),
          child: Text(
            row.verdict,
            style: TextStyle(
              color: _verdictColor(),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

// Lightweight node-graph painter for the ambient background.
class _NodeGraphPainter extends CustomPainter {
  const _NodeGraphPainter();

  // Seeded positions so the graph is stable across repaints.
  static final List<Offset> _nodes = _buildNodes();

  static List<Offset> _buildNodes() {
    final rng = math.Random(42);
    return List.generate(24, (_) => Offset(rng.nextDouble(), rng.nextDouble()));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()
      ..color = const Color(0xFF1E3A5F).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final edgePaint = Paint()
      ..color = const Color(0xFF1E3A5F).withValues(alpha: 0.18)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final positions = _nodes
        .map((n) => Offset(n.dx * size.width, n.dy * size.height))
        .toList();

    // Draw edges between nearby nodes.
    for (var i = 0; i < positions.length; i++) {
      for (var j = i + 1; j < positions.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d < size.width * 0.28) {
          canvas.drawLine(positions[i], positions[j], edgePaint);
        }
      }
    }

    // Draw nodes.
    for (final p in positions) {
      canvas.drawCircle(p, 3, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
