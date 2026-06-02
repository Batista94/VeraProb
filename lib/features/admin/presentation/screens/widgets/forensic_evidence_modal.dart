import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/core/utils/jwt_utils.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/forensic_evidence_providers.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';

/// Modal dialog that displays a read-only "Forensic Evidence Snapshot"
/// of a sealed verdict.
///
/// **Enterprise Hardening Details:**
/// - **Resilience:** Wrapped in a [SingleChildScrollView] with a max height
///   constraint of `85%` of the screen height to prevent overflows.
/// - **Imutabilidade Visual:** Zero inputs (TextFields, Dropdowns) and no
///   Save/Edit buttons. Uses lock icons and "Cópia Autenticada" badges.
/// - **Anti-Tampering & Escalation:** On [IntegrityException], it triggers
///   a silent security log immediately and presents a button to manually
///   escalate the incident to SOC administrators.
/// - **Timezone Translation:** All UTC timestamps are translated to the
///   operator's local time and suffix the timezone abbreviation (e.g. BRT).
class ForensicEvidenceModal extends ConsumerStatefulWidget {
  final String ledgerEntryId;

  const ForensicEvidenceModal({super.key, required this.ledgerEntryId});

  @override
  ConsumerState<ForensicEvidenceModal> createState() =>
      _ForensicEvidenceModalState();
}

class _ForensicEvidenceModalState extends ConsumerState<ForensicEvidenceModal> {
  bool _hasLoggedTampering = false;
  bool _isEscalating = false;

  void _logTamperedIncident(WidgetRef ref) {
    if (_hasLoggedTampering) return;
    _hasLoggedTampering = true;

    final session = ref.read(authStateProvider).value?.session;
    final sanitizedClaims = _sanitizeJwtClaims(session?.accessToken);

    ref
        .read(securityIncidentLoggerProvider)
        .log(
          eventType: 'FORENSIC_INTEGRITY_COMPROMISED',
          metadata: {
            'ledger_entry_id': widget.ledgerEntryId,
            'source': 'forensic_evidence_modal_tampered_warning',
            'details':
                'Integrity check failed: local hash mismatch with database.',
          },
          jwtClaimsSnapshot: sanitizedClaims,
        );
  }

  Future<void> _escalateIncident(WidgetRef ref) async {
    setState(() => _isEscalating = true);
    try {
      final session = ref.read(authStateProvider).value?.session;
      final sanitizedClaims = _sanitizeJwtClaims(session?.accessToken);

      await ref
          .read(securityIncidentLoggerProvider)
          .log(
            eventType: 'SECURITY_INCIDENT_ESCALATION_REQUESTED',
            metadata: {
              'ledger_entry_id': widget.ledgerEntryId,
              'source': 'forensic_evidence_modal_escalation',
              'reason':
                  'Operator requested incident escalation due to integrity breach.',
            },
            jwtClaimsSnapshot: sanitizedClaims,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incidente de segurança escalado com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isEscalating = false);
    }
  }

  Map<String, dynamic> _sanitizeJwtClaims(String? accessToken) {
    if (accessToken == null) return {};
    try {
      final claims = decodeJwtPayload(accessToken);
      final sanitized = <String, dynamic>{};
      if (claims.containsKey('sub')) sanitized['sub'] = claims['sub'];
      if (claims.containsKey('aal')) sanitized['aal'] = claims['aal'];
      if (claims.containsKey('role')) sanitized['role'] = claims['role'];
      final appMeta = claims['app_metadata'] as Map<String, dynamic>?;
      if (appMeta != null) {
        final sanitizedMeta = <String, dynamic>{};
        if (appMeta.containsKey('super_admin')) {
          sanitizedMeta['super_admin'] = appMeta['super_admin'];
        }
        if (appMeta.containsKey('org_id')) {
          sanitizedMeta['org_id'] = appMeta['org_id'];
        }
        sanitized['app_metadata'] = sanitizedMeta;
      }
      return sanitized;
    } catch (_) {
      return {};
    }
  }

  String _formatLocalDateWithTimezone(DateTime? utc) {
    if (utc == null) return 'N/A';
    final local = utc.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');

    final dateStr =
        '${pad(local.day)}/${pad(local.month)}/${local.year} '
        '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';

    return '$dateStr (${local.timeZoneName})';
  }

  String _formatFine(int cents) {
    final value = cents / 100.0;
    final whole = value.floor();
    final decimal = ((value - whole) * 100).round().toString().padLeft(2, '0');
    String formatThousands(int n) {
      final s = n.toString();
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
        buf.write(s[i]);
      }
      return buf.toString();
    }

    return 'R\$ ${formatThousands(whole)},$decimal';
  }

  Widget _buildRuleConfigHuman(RuleSnapshotItem rule) {
    final config = rule.config;
    final type = rule.ruleType;

    return switch (type) {
      SlaRuleType.maxToleranceDelay => _buildReadOnlyRow(
        'Tolerância Máxima de Atraso',
        '${config['threshold_minutes'] ?? 'N/A'} minutos',
      ),
      SlaRuleType.maxEvidenceGap => _buildReadOnlyRow(
        'Intervalo Máximo de Evidência',
        '${config['max_gap_seconds'] ?? 'N/A'} segundos',
      ),
      SlaRuleType.minGeofenceCoverage => _buildReadOnlyRow(
        'Tempo Mínimo na Cerca Virtual',
        '${config['min_dwell_seconds'] ?? 'N/A'} segundos',
      ),
      SlaRuleType.noShowPenalty => _buildReadOnlyRow(
        'Valor da Penalidade por No-Show',
        _formatFine((config['penalty_amount_cents'] as num?)?.toInt() ?? 0),
      ),
      SlaRuleType.requiredEvidence => () {
        final typesList = config['types'] as List?;
        final typesStr = typesList?.join(', ') ?? 'Nenhuma';
        return _buildReadOnlyRow('Evidências Obrigatórias', typesStr);
      }(),
      SlaRuleType.excessiveSpeed => _buildReadOnlyRow(
        'Velocidade Excessiva',
        config.entries.map((e) => '${e.key}: ${e.value}').join(', '),
      ),
    };
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: VeraProbTypography.fieldLabel.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: VeraProbColors.textDisabled,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    style: VeraProbTypography.bodyMedium.copyWith(
                      color: VeraProbColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verificationAsync = ref.watch(
      forensicEvidenceVerificationProvider(widget.ledgerEntryId),
    );

    // Listen for integrity compromises to log silently exactly once.
    ref.listen<AsyncValue<EvidenceVerification>>(
      forensicEvidenceVerificationProvider(widget.ledgerEntryId),
      (previous, next) {
        if (next is AsyncError && next.error is IntegrityException) {
          _logTamperedIncident(ref);
        }
      },
    );

    return Dialog(
      backgroundColor: VeraProbColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VeraProbColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Title
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: VeraProbColors.border),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: VeraProbColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Cópia Forense da Regra',
                    style: VeraProbTypography.sectionTitle.copyWith(
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                    color: VeraProbColors.textSecondary,
                  ),
                ],
              ),
            ),

            // Scrollable Content Pane
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: switch (verificationAsync) {
                  AsyncLoading() => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  AsyncError(:final error) => () {
                    if (error is IntegrityException) {
                      return _buildTamperedView();
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          'Erro ao carregar evidência: $error',
                          style: const TextStyle(color: VeraProbColors.error),
                        ),
                      ),
                    );
                  }(),
                  AsyncData(:final value) => _buildAuthenticView(
                    value.snapshot,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthenticView(ForensicEvidenceSnapshot snapshot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trust badge banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: VeraProbColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: VeraProbColors.success.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.verified_user,
                color: VeraProbColors.success,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cópia Autenticada',
                  style: VeraProbTypography.badge.copyWith(
                    color: VeraProbColors.success,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Section: Signatures
        Text(
          'INFORMAÇÕES DE REGISTRO',
          style: VeraProbTypography.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VeraProbColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VeraProbColors.border),
          ),
          child: Column(
            children: [
              _buildReadOnlyRow(
                'Vigência Início',
                _formatLocalDateWithTimezone(snapshot.effectiveFromUtc),
              ),
              _buildReadOnlyRow(
                'Vigência Fim',
                _formatLocalDateWithTimezone(snapshot.effectiveToUtc),
              ),
              _buildReadOnlyRow('Selado Por (Operador)', snapshot.sealedBy),
              _buildReadOnlyRow(
                'Selado Em (Data)',
                _formatLocalDateWithTimezone(snapshot.sealedAtUtc),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Section: Frozen Parameters
        Text(
          'PARÂMETROS CONGELADOS',
          style: VeraProbTypography.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        ...snapshot.rules.rules.map((rule) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VeraProbColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.lock,
                      size: 14,
                      color: VeraProbColors.textDisabled,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Regra: ${rule.ruleId}',
                      style: VeraProbTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: VeraProbColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'v${rule.ruleVersion}',
                        style: VeraProbTypography.badge.copyWith(
                          color: VeraProbColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(color: VeraProbColors.border),
                const SizedBox(height: 8),
                _buildRuleConfigHuman(rule),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),

        // Section: Cryptographic Seals
        Text(
          'VERIFICAÇÃO CRIPTOGRÁFICA',
          style: VeraProbTypography.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VeraProbColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VeraProbColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hash Selado (SHA-256):',
                style: VeraProbTypography.fieldLabel,
              ),
              const SizedBox(height: 4),
              SelectableText(
                snapshot.integrityHash,
                style: VeraProbTypography.caption.copyWith(
                  fontFamily: 'monospace',
                  color: VeraProbColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTamperedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Error banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VeraProbColors.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: VeraProbColors.error.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.gavel_rounded,
                color: VeraProbColors.error,
                size: 24,
              ),
              const SizedBox(height: 10),
              Text(
                'Divergência Crítica de Integridade',
                textAlign: TextAlign.center,
                style: VeraProbTypography.sectionTitle.copyWith(
                  color: VeraProbColors.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Suspeita de Fraude no Banco de Dados. Os parâmetros desta regra '
                'foram adulterados após o selamento do veredito.',
                textAlign: TextAlign.center,
                style: VeraProbTypography.bodySmall.copyWith(
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Block parameters read-out message
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VeraProbColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VeraProbColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.lock_outline,
                color: VeraProbColors.textDisabled,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'A leitura dos parâmetros desta cópia foi bloqueada de forma '
                  'preventiva por motivos de segurança.',
                  style: VeraProbTypography.bodyMedium.copyWith(
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Escalate incident CTA
        ElevatedButton.icon(
          onPressed: _isEscalating ? null : () => _escalateIncident(ref),
          icon: _isEscalating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.report_gmailerrorred),
          label: const Text('ESCALAR INCIDENTE'),
          style: ElevatedButton.styleFrom(
            backgroundColor: VeraProbColors.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
