import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/super_admin/application/tenant_technical_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/pulse_indicator.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Tab de Saúde Técnica do tenant — exibe indicadores de replicação e schema.
///
/// Consome [tenantTechnicalHealthProvider] via `ref.watch` e renderiza dois
/// [PulseIndicator] widgets: um para status de replicação e outro para
/// integridade de schema. Exibe versão do schema e timestamp da última
/// verificação quando disponível.
///
/// **INV-11:** Dispose adequado de recursos; construtores `const` onde possível.
/// **INV-22:** Reside em `lib/features/super_admin/presentation/widgets/`.
///
/// **Validates: Requirements 1.3, 2.1, 2.2, 2.4, 4.1, 4.2, 4.3, 4.4, 10.1, 10.4**
class TenantHealthTab extends ConsumerStatefulWidget {
  final String organizationId;

  const TenantHealthTab({super.key, required this.organizationId});

  @override
  ConsumerState<TenantHealthTab> createState() => _TenantHealthTabState();
}

class _TenantHealthTabState extends ConsumerState<TenantHealthTab>
    with SingleTickerProviderStateMixin {
  /// Whether a schema integrity check is currently in progress.
  bool _isChecking = false;

  /// Whether the 3-second cooldown after a check is active (Req 3.4, 3.5).
  bool _cooldownActive = false;

  /// Error message from the last failed integrity check (Req 3.3).
  String? _checkError;

  /// Cooldown timer — disposed in [dispose] to avoid leaks (INV-11).
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Triggers an on-demand schema integrity check via Edge Function proxy
  /// (INV-14). Uses `ref.read` for a one-shot action (Req 10.4).
  Future<void> _checkIntegrity() async {
    if (_isChecking || _cooldownActive) return;

    setState(() {
      _isChecking = true;
      _checkError = null;
    });

    try {
      // Req 3.6: Invoke check exclusively via Edge Function proxy.
      await ref
          .read(superAdminRepositoryProvider)
          .checkSchemaIntegrity(widget.organizationId);

      // Req 3.2: On success, refresh the health provider to update
      // the PulseIndicator with the new schema integrity result.
      ref.invalidate(tenantTechnicalHealthProvider(widget.organizationId));
    } catch (e) {
      // Req 3.3: Show contextual error without freezing the UI.
      setState(() {
        _checkError = 'Falha na verificação: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _cooldownActive = true;
        });

        // Req 3.4: 3-second debounce cooldown.
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _cooldownActive = false;
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Req 4.3/4.4: Validate JWT claim BEFORE dispatching any RPC calls.
    // Consumes session via SuperAdminSessionProvider (isSuperAdminProvider),
    // NOT the client UserProvider.
    final isSuperAdmin = ref.watch(isSuperAdminProvider);

    if (!isSuperAdmin) {
      return _buildUnauthorizedBlur();
    }

    // Req 4.1: Authorized — render health indicators normally.
    final healthAsync = ref.watch(
      tenantTechnicalHealthProvider(widget.organizationId),
    );

    return healthAsync.when(
      loading: _buildLoading,
      error: (error, _) => _buildError(error),
      data: _buildData,
    );
  }

  /// Req 4.2: Renders a blur overlay over placeholder content to indicate
  /// that sensitive data exists but is not accessible to the current user.
  Widget _buildUnauthorizedBlur() {
    return Stack(
      children: [
        // Placeholder content behind the blur — shows structure without
        // revealing real data.
        SingleChildScrollView(
          padding: const EdgeInsets.all(VeraProbSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Replicação', style: VeraProbTypography.sectionTitle),
              const SizedBox(height: VeraProbSpacing.md),
              Container(
                height: 60,
                decoration: BoxDecoration(
                  color: VeraProbColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: VeraProbSpacing.lg),
              const Divider(),
              const SizedBox(height: VeraProbSpacing.lg),
              Text(
                'Integridade de Schema',
                style: VeraProbTypography.sectionTitle,
              ),
              const SizedBox(height: VeraProbSpacing.md),
              Container(
                height: 60,
                decoration: BoxDecoration(
                  color: VeraProbColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
        // BackdropFilter blur overlay (Req 4.2).
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: VeraProbColors.background.withValues(alpha: 0.3),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 48,
                      color: VeraProbColors.textSecondary,
                    ),
                    const SizedBox(height: VeraProbSpacing.md),
                    Text(
                      'Acesso não autorizado',
                      style: VeraProbTypography.sectionTitle,
                    ),
                    const SizedBox(height: VeraProbSpacing.sm),
                    Text(
                      'Você não possui permissão para visualizar\n'
                      'dados de saúde técnica.',
                      style: VeraProbTypography.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(VeraProbSpacing.xl),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VeraProbSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: VeraProbColors.error,
              size: 48,
            ),
            const SizedBox(height: VeraProbSpacing.md),
            Text(
              'Erro ao carregar saúde técnica',
              style: VeraProbTypography.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            Text(
              error.toString(),
              style: VeraProbTypography.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildData(TenantTechnicalHealthView health) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Seção: Replicação ──────────────────────────────
          Text('Replicação', style: VeraProbTypography.sectionTitle),
          const SizedBox(height: VeraProbSpacing.md),
          PulseIndicator(
            label: 'Status de Replicação',
            status: health.replicationStatus.toPulseStatus(),
            subtitle: _replicationSubtitle(health.replicationStatus),
          ),

          const SizedBox(height: VeraProbSpacing.lg),
          const Divider(),
          const SizedBox(height: VeraProbSpacing.lg),

          // ── Seção: Integridade de Schema ───────────────────
          Text('Integridade de Schema', style: VeraProbTypography.sectionTitle),
          const SizedBox(height: VeraProbSpacing.md),
          PulseIndicator(
            label: 'Integridade de Schema',
            status: health.schemaIntegrityStatus.toPulseStatus(),
            subtitle: _schemaSubtitle(health.schemaIntegrityStatus),
          ),

          const SizedBox(height: VeraProbSpacing.md),

          // ── Versão do Schema ──────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.code,
                size: 16,
                color: VeraProbColors.textSecondary,
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              Text('Versão: ', style: VeraProbTypography.bodySmall),
              Text(
                health.schemaVersion,
                style: VeraProbTypography.bodyMedium.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          // ── Última Verificação ────────────────────────────
          if (health.lastCheckAt != null) ...[
            const SizedBox(height: VeraProbSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.schedule,
                  size: 16,
                  color: VeraProbColors.textSecondary,
                ),
                const SizedBox(width: VeraProbSpacing.sm),
                Text(
                  'Última verificação: ',
                  style: VeraProbTypography.bodySmall,
                ),
                Text(
                  _formatDateTime(health.lastCheckAt!),
                  style: VeraProbTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: VeraProbSpacing.lg),

          // ── Botão: Verificar Integridade (Req 3.1–3.6) ───
          _buildIntegrityCheckButton(),

          // ── Erro contextual da verificação (Req 3.3) ──────
          if (_checkError != null) ...[
            const SizedBox(height: VeraProbSpacing.sm),
            Text(
              _checkError!,
              style: VeraProbTypography.bodySmall.copyWith(
                color: VeraProbColors.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the "Verificar Integridade" button with three visual states:
  ///
  /// - **Normal**: "Verificar Integridade" with [Icons.verified_outlined]
  /// - **Loading**: [CircularProgressIndicator] while check is in progress
  /// - **Cooldown**: Disabled with "Aguarde..." text (Req 3.4, 3.5)
  Widget _buildIntegrityCheckButton() {
    final isDisabled = _isChecking || _cooldownActive;

    return ElevatedButton.icon(
      onPressed: isDisabled ? null : _checkIntegrity,
      icon: _isChecking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VeraProbColors.textSecondary,
              ),
            )
          : const Icon(Icons.verified_outlined, size: 18),
      label: Text(
        _isChecking
            ? 'Verificando...'
            : _cooldownActive
            ? 'Aguarde...'
            : 'Verificar Integridade',
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: VeraProbColors.surface,
        foregroundColor: VeraProbColors.textPrimary,
        disabledBackgroundColor: VeraProbColors.surface.withValues(alpha: 0.5),
        disabledForegroundColor: VeraProbColors.textSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: VeraProbSpacing.md,
          vertical: VeraProbSpacing.sm,
        ),
      ),
    );
  }

  /// Retorna um subtítulo descritivo para o status de replicação.
  String _replicationSubtitle(ReplicationStatus status) {
    return switch (status) {
      ReplicationStatus.healthy => 'Replicação saudável',
      ReplicationStatus.delayed => 'Replicação com atraso',
      ReplicationStatus.failed => 'Falha na replicação',
      ReplicationStatus.unknown => 'Status desconhecido',
    };
  }

  /// Retorna um subtítulo descritivo para o status de integridade de schema.
  String _schemaSubtitle(SchemaIntegrityStatus status) {
    return switch (status) {
      SchemaIntegrityStatus.compliant => 'Schema conforme',
      SchemaIntegrityStatus.minorDrift => 'Divergência menor detectada',
      SchemaIntegrityStatus.criticalDrift => 'Divergência crítica detectada',
      SchemaIntegrityStatus.unknown => 'Status desconhecido',
    };
  }

  /// Formata um [DateTime] para exibição legível (dd/MM HH:mm).
  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
