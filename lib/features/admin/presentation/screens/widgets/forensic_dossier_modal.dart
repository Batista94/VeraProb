import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/evidence_snapshot_view.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/core/utils/jwt_utils.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/investigation_modal.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/forensic_evidence_providers.dart';
import 'package:veraprob/state/providers/investigation_providers.dart';
import 'package:flutter/services.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart'; // pr_scanner: ignore
import 'package:veraprob/state/providers/dispute_evidence_providers.dart';

/// Tab indices for [ForensicDossierModal]. Used by deep-links from the card
/// (e.g. the custody-chain row jumps straight to [custody]).
enum ForensicDossierTab { evidence, custody, decisions, rule }

/// Single, consolidated forensic dossier for a sealed verdict.
///
/// Replaces the two previously-separate (and mislabeled) modals with one tabbed
/// surface:
///   1. **Evidência** — raw telemetry that triggered the sanction (speed, GPS,
///      geofence, delay) extracted from the engine evaluation traces.
///   2. **Cadeia de Custódia** — SHA-256 seal, who/when sealed, integrity verify.
///   3. **Decisões** — humanized ledger timeline + engine evaluation traces.
///   4. **Regra** — frozen clause parameters at seal time.
///
/// Custody + Regra read a single forensic snapshot via
/// [forensicEvidenceVerificationByQueueProvider]; on integrity failure the modal
/// logs a silent security incident once and blocks parameter read-out, exactly
/// as the legacy evidence modal did (INV-9, INV-22).
class ForensicDossierModal extends ConsumerStatefulWidget {
  final String setId;
  final String contractId;
  final String queueEntryId;
  final ForensicDossierTab initialTab;

  const ForensicDossierModal({
    super.key,
    required this.setId,
    required this.contractId,
    required this.queueEntryId,
    this.initialTab = ForensicDossierTab.evidence,
  });

  @override
  ConsumerState<ForensicDossierModal> createState() =>
      _ForensicDossierModalState();
}

class _ForensicDossierModalState extends ConsumerState<ForensicDossierModal>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _hasLoggedTampering = false;
  bool _isEscalating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _logTamperedIncident() {
    if (_hasLoggedTampering) return;
    _hasLoggedTampering = true;

    final session = ref.read(authStateProvider).value?.session;
    final sanitizedClaims = _sanitizeJwtClaims(session?.accessToken);

    ref
        .read(securityIncidentLoggerProvider)
        .log(
          eventType: 'FORENSIC_INTEGRITY_COMPROMISED',
          metadata: {
            'queue_entry_id': widget.queueEntryId,
            'source': 'forensic_dossier_modal_tampered_warning',
            'details':
                'Integrity check failed: local hash mismatch with database.',
          },
          jwtClaimsSnapshot: sanitizedClaims,
        );
  }

  Future<void> _escalateIncident() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isEscalating = true);
    try {
      final session = ref.read(authStateProvider).value?.session;
      final sanitizedClaims = _sanitizeJwtClaims(session?.accessToken);

      await ref
          .read(securityIncidentLoggerProvider)
          .log(
            eventType: 'SECURITY_INCIDENT_ESCALATION_REQUESTED',
            metadata: {
              'queue_entry_id': widget.queueEntryId,
              'source': 'forensic_dossier_modal_escalation',
              'reason':
                  'Operator requested incident escalation due to integrity breach.',
            },
            jwtClaimsSnapshot: sanitizedClaims,
          );

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Incidente de segurança escalado com sucesso.'),
          backgroundColor: VeraProbColors.success,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    // Listen for tampered status to log silently exactly once.
    ref.listen<AsyncValue<EvidenceSnapshotView>>(
      forensicEvidenceVerificationByQueueProvider(widget.queueEntryId),
      (previous, next) {
        if (next is AsyncData &&
            next.value!.status == EvidenceSnapshotStatus.tampered) {
          _logTamperedIncident();
        }
      },
    );

    return Dialog(
      backgroundColor: VeraProbColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1100,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DossierHeader(onClose: () => Navigator.pop(context)),
            Container(
              decoration: const BoxDecoration(
                color: VeraProbColors.surface,
                border: Border(
                  bottom: BorderSide(color: VeraProbColors.border),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: VeraProbColors.primary,
                unselectedLabelColor: VeraProbColors.textSecondary,
                indicatorColor: VeraProbColors.primary,
                labelStyle: VeraProbTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Evidência'),
                  Tab(text: 'Cadeia de Custódia'),
                  Tab(text: 'Decisões'),
                  Tab(text: 'Regra'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RawEvidenceTab(
                    setId: widget.setId,
                    queueEntryId: widget.queueEntryId,
                  ),
                  _CustodyChainTab(
                    queueEntryId: widget.queueEntryId,
                    isEscalating: _isEscalating,
                    onEscalate: _escalateIncident,
                  ),
                  InvestigationDossierBody(
                    setId: widget.setId,
                    contractId: widget.contractId,
                    showTraces: false,
                  ),
                  _FrozenRuleTab(queueEntryId: widget.queueEntryId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Header
// ═══════════════════════════════════════════════════════════════

class _DossierHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _DossierHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: VeraProbColors.border)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 18,
            color: VeraProbColors.primary,
          ),
          const SizedBox(width: 8),
          Text('Dossiê Forense', style: VeraProbTypography.sectionTitle),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: VeraProbColors.border),
            ),
            child: Text(
              'MODO AUDITORIA',
              style: VeraProbTypography.caption.copyWith(
                color: VeraProbColors.warning,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.close),
            color: VeraProbColors.textSecondary,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _RawEvidenceTab extends ConsumerWidget {
  final String setId;
  final String queueEntryId;
  const _RawEvidenceTab({required this.setId, required this.queueEntryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracesAsync = ref.watch(evaluationTracesProvider(setId));
    final evidenceAsync = ref.watch(disputeEvidenceListProvider(queueEntryId));

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'EVIDÊNCIAS ANEXADAS',
          style: VeraProbTypography.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Documentos e fotos anexados pela transportadora.',
          style: VeraProbTypography.bodySmall.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        switch (evidenceAsync) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError() => const Text(
            'Não foi possível carregar as evidências anexadas.',
            style: TextStyle(color: VeraProbColors.error),
          ),
          AsyncData(:final value) =>
            value.isEmpty
                ? Text(
                    'Nenhuma evidência anexada pela transportadora.',
                    style: VeraProbTypography.bodyMedium.copyWith(
                      color: VeraProbColors.textDisabled,
                    ),
                  )
                : Column(
                    children: value
                        .map((e) => _EvidenceManifestCard(attachment: e))
                        .toList(),
                  ),
        },
        const SizedBox(height: 32),
        const Divider(color: VeraProbColors.border),
        const SizedBox(height: 24),
        Text(
          'AVALIAÇÃO DO MOTOR FORENSE',
          style: VeraProbTypography.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Dados físicos capturados que dispararam a avaliação contratual.',
          style: VeraProbTypography.bodySmall.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        switch (tracesAsync) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError() => const Text(
            'Não foi possível carregar a avaliação do motor.',
            style: TextStyle(color: VeraProbColors.error),
          ),
          AsyncData(:final value) => _buildDecisionList(value),
        },
      ],
    );
  }

  Widget _buildDecisionList(List<EvaluationTrace> value) {
    final decisions = value.expand((t) => t.decisions).toList();
    if (decisions.isEmpty) {
      return const Text(
        'Sem telemetria',
        style: TextStyle(color: VeraProbColors.textDisabled),
      );
    }
    return Column(
      children: decisions.map((d) => _RawEvidenceCard(decision: d)).toList(),
    );
  }
}

class _EvidenceManifestCard extends StatelessWidget {
  final DisputeEvidenceAttachment attachment;
  const _EvidenceManifestCard({required this.attachment});

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = attachment.fileName.toLowerCase().endsWith('.pdf');
    final (
      badgeColor,
      badgeIcon,
      badgeLabel,
      tooltip,
    ) = switch (attachment.verificationStatus) {
      EvidenceVerificationStatus.verified => (
        VeraProbColors.onTime,
        Icons.verified_outlined,
        'VERIFICADO',
        'Assinatura digital íntegra e verificada',
      ),
      EvidenceVerificationStatus.mismatch => (
        VeraProbColors.error,
        Icons.gpp_bad_outlined,
        'DIVERGENTE',
        'Adulteração detectada. Não use como prova.',
      ),
      EvidenceVerificationStatus.pending => (
        VeraProbColors.warning,
        Icons.hourglass_empty_outlined,
        'PENDENTE',
        'Aguardando verificação. Não use como prova.',
      ),
    };

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
              Icon(
                isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                size: 20,
                color: VeraProbColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      style: VeraProbTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: VeraProbColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatSize(attachment.fileSizeBytes)} • Anexado em ${_formatLocalDateWithTimezone(attachment.attachedAtUtc)}',
                      style: VeraProbTypography.caption.copyWith(
                        color: VeraProbColors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: tooltip,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(badgeIcon, size: 12, color: badgeColor),
                      const SizedBox(width: 4),
                      Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.fingerprint,
                size: 14,
                color: VeraProbColors.textDisabled,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  attachment.sha256Hash,
                  style: VeraProbTypography.caption.copyWith(
                    fontFamily: 'monospace',
                    color: VeraProbColors.textDisabled,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.copy,
                  size: 14,
                  color: VeraProbColors.textDisabled,
                ),
                tooltip: 'Copiar hash',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: attachment.sha256Hash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Hash copiado para a área de transferência',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RawEvidenceCard extends StatelessWidget {
  final EvaluationDecision decision;
  const _RawEvidenceCard({required this.decision});

  @override
  Widget build(BuildContext context) {
    final rows = _evidenceRows(decision.evidence);

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
                Icons.fact_check_outlined,
                size: 16,
                color: VeraProbColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  decision.ruleType,
                  style: VeraProbTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: VeraProbColors.border, height: 1),
          const SizedBox(height: 8),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      r.label,
                      style: VeraProbTypography.fieldLabel.copyWith(
                        color: VeraProbColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(
                      r.value,
                      style: VeraProbTypography.bodyMedium.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: r.highlight
                            ? VeraProbColors.error
                            : VeraProbColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single human-readable telemetry field.
class _EvidenceRow {
  final String label;
  final String value;
  final bool highlight;
  const _EvidenceRow(this.label, this.value, {this.highlight = false});
}

String _kmh(double v) => '${v.toStringAsFixed(1)} km/h';
String _gps(double lat, double lng) =>
    '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

/// Maps a typed [EvidencePayload] to display rows. Falls back to the raw JSON
/// key/value pairs for legacy/generic payloads so nothing is hidden.
List<_EvidenceRow> _evidenceRows(EvidencePayload evidence) {
  switch (evidence) {
    case SpeedViolationEvidence(:final actualSpeedKmh, :final limitSpeedKmh):
      final over = actualSpeedKmh - limitSpeedKmh;
      return [
        _EvidenceRow(
          'Velocidade aferida',
          _kmh(actualSpeedKmh),
          highlight: over > 0,
        ),
        _EvidenceRow('Limite contratual', _kmh(limitSpeedKmh)),
        if (over > 0)
          _EvidenceRow('Excesso', '+${_kmh(over)}', highlight: true),
      ];
    case GeofenceBindingEvidence(
      :final distanceMeters,
      :final allowedRadiusMeters,
      :final actualDwellSeconds,
      :final requiredDwellSeconds,
    ):
      return [
        _EvidenceRow(
          'Distância ao centro',
          '${distanceMeters.toStringAsFixed(1)} m',
        ),
        _EvidenceRow('Raio permitido', '$allowedRadiusMeters m'),
        _EvidenceRow('Permanência aferida', '$actualDwellSeconds s'),
        _EvidenceRow('Permanência exigida', '$requiredDwellSeconds s'),
      ];
    case InterpolatedPassageEvidence(
      :final fromLat,
      :final fromLng,
      :final toLat,
      :final toLng,
      :final geofenceCenterLat,
      :final geofenceCenterLng,
      :final geofenceRadiusMeters,
    ):
      return [
        _EvidenceRow('GPS origem', _gps(fromLat, fromLng)),
        _EvidenceRow('GPS destino', _gps(toLat, toLng)),
        _EvidenceRow(
          'Centro da cerca',
          _gps(geofenceCenterLat, geofenceCenterLng),
        ),
        _EvidenceRow(
          'Raio da cerca',
          '${geofenceRadiusMeters.toStringAsFixed(1)} m',
        ),
      ];
    case DelayPenaltyEvidence(
      :final delayMinutes,
      :final toleranceMinutes,
      :final billableMinutes,
    ):
      return [
        _EvidenceRow('Atraso aferido', '$delayMinutes min', highlight: true),
        _EvidenceRow('Tolerância', '$toleranceMinutes min'),
        _EvidenceRow('Minutos faturáveis', '$billableMinutes min'),
      ];
    case _:
      final json = evidence.toJson()..removeWhere((key, _) => key == '_type');
      if (json.isEmpty) {
        return const [_EvidenceRow('Evidência', 'Sem dados físicos')];
      }
      return json.entries
          .map((e) => _EvidenceRow(e.key, '${e.value}'))
          .toList();
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab 2 — Custody Chain (seal + integrity)
// ═══════════════════════════════════════════════════════════════

class _CustodyChainTab extends ConsumerWidget {
  final String queueEntryId;
  final bool isEscalating;
  final Future<void> Function() onEscalate;

  const _CustodyChainTab({
    required this.queueEntryId,
    required this.isEscalating,
    required this.onEscalate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verificationAsync = ref.watch(
      forensicEvidenceVerificationByQueueProvider(queueEntryId),
    );

    return switch (verificationAsync) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Não foi possível carregar a evidência de integridade.',
            style: TextStyle(color: VeraProbColors.error),
          ),
        ),
      ),
      AsyncData(:final value) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: value.status == EvidenceSnapshotStatus.tampered
            ? _TamperedView(isEscalating: isEscalating, onEscalate: onEscalate)
            : _CustodyAuthenticView(
                snapshot: value,
                queueEntryId: queueEntryId,
              ),
      ),
    };
  }
}

class _CustodyAuthenticView extends ConsumerWidget {
  final EvidenceSnapshotView snapshot;
  final String queueEntryId;
  const _CustodyAuthenticView({
    required this.snapshot,
    required this.queueEntryId,
  });

  String _shortenUuid(String uuid) {
    final parts = uuid.split('-');
    if (parts.length > 1) {
      return '${parts[0]}-${parts[1]}...';
    }
    return uuid.length > 8 ? '${uuid.substring(0, 8)}...' : uuid;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provenance = ref.watch(verdictProvenanceProvider(queueEntryId)).value;
    final actorEmail = provenance?.actorEmail;
    final auditorNote = provenance?.auditorNote?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              _LockedRow(
                'Vigência Início',
                _formatLocalDateWithTimezone(snapshot.effectiveFromUtc),
              ),
              _LockedRow(
                'Vigência Fim',
                _formatLocalDateWithTimezone(snapshot.effectiveToUtc),
              ),
              if (actorEmail != null && actorEmail.isNotEmpty)
                _LockedRow(
                  'Selado Por',
                  actorEmail,
                  tooltip: 'Identificador Interno: ${snapshot.sealedBy}',
                )
              else
                _LockedRow(
                  'Selado Por (Operador)',
                  _shortenUuid(snapshot.sealedBy),
                ),
              _LockedRow(
                'Selado Em (Data)',
                _formatLocalDateWithTimezone(snapshot.sealedAtUtc),
              ),
            ],
          ),
        ),
        if (auditorNote != null && auditorNote.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'JUSTIFICATIVA DO AUDITOR',
            style: VeraProbTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VeraProbColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.format_quote,
                  size: 16,
                  color: VeraProbColors.textDisabled,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    auditorNote,
                    style: VeraProbTypography.bodyMedium.copyWith(
                      color: VeraProbColors.textPrimary,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
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
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      snapshot.integrityHash,
                      style: VeraProbTypography.caption.copyWith(
                        fontFamily: 'monospace',
                        color: VeraProbColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.copy,
                      size: 16,
                      color: VeraProbColors.textDisabled,
                    ),
                    tooltip: 'Copiar hash',
                    onPressed: () {
                      final messenger = ScaffoldMessenger.of(context);
                      Clipboard.setData(
                        ClipboardData(text: snapshot.integrityHash),
                      );
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Hash copiado para a área de transferência',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab 4 — Frozen Rule parameters
// ═══════════════════════════════════════════════════════════════

class _FrozenRuleTab extends ConsumerWidget {
  final String queueEntryId;
  const _FrozenRuleTab({required this.queueEntryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verificationAsync = ref.watch(
      forensicEvidenceVerificationByQueueProvider(queueEntryId),
    );

    return switch (verificationAsync) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Não foi possível carregar as regras contratuais.',
            style: TextStyle(color: VeraProbColors.error),
          ),
        ),
      ),
      AsyncData(:final value) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: value.status == EvidenceSnapshotStatus.tampered
            ? _RuleBlockedView()
            : _FrozenRuleView(snapshot: value),
      ),
    };
  }
}

class _FrozenRuleView extends StatelessWidget {
  final EvidenceSnapshotView snapshot;
  const _FrozenRuleView({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PARÂMETROS CONGELADOS',
          style: VeraProbTypography.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        ...snapshot.rules.map((rule) {
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
      ],
    );
  }
}

class _RuleBlockedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: VeraProbColors.textDisabled),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Tampered escalation view (shared shell — custody tab)
// ═══════════════════════════════════════════════════════════════

class _TamperedView extends StatelessWidget {
  final bool isEscalating;
  final Future<void> Function() onEscalate;

  const _TamperedView({required this.isEscalating, required this.onEscalate});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        _RuleBlockedView(),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: isEscalating ? null : () => onEscalate(),
          icon: isEscalating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: VeraProbColors.background,
                  ),
                )
              : const Icon(Icons.report_gmailerrorred),
          label: const Text('ESCALAR INCIDENTE'),
          // ACCENT-FILL-CONTRAST: dark fg on fill.
          style: ElevatedButton.styleFrom(
            backgroundColor: VeraProbColors.error,
            foregroundColor: VeraProbColors.background,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Shared helpers
// ═══════════════════════════════════════════════════════════════

class _LockedRow extends StatelessWidget {
  final String label;
  final String value;
  final String? tooltip;
  const _LockedRow(this.label, this.value, {this.tooltip});

  @override
  Widget build(BuildContext context) {
    final valueWidget = Text(
      value,
      style: VeraProbTypography.bodyMedium.copyWith(
        color: VeraProbColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );

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
                  child: tooltip != null
                      ? Tooltip(message: tooltip, child: valueWidget)
                      : valueWidget,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildRuleConfigHuman(FrozenRuleView rule) {
  final config = rule.config;
  return switch (rule.ruleTypeKey) {
    'MAX_TOLERANCE_DELAY' => _LockedRow(
      'Tolerância Máxima de Atraso',
      '${config['threshold_minutes'] ?? 'N/A'} minutos',
    ),
    'MAX_EVIDENCE_GAP' => _LockedRow(
      'Intervalo Máximo de Evidência',
      '${config['max_gap_seconds'] ?? 'N/A'} segundos',
    ),
    'MIN_GEOFENCE_COVERAGE' => _LockedRow(
      'Tempo Mínimo na Cerca Virtual',
      '${config['min_dwell_seconds'] ?? 'N/A'} segundos',
    ),
    'NO_SHOW_PENALTY' => _LockedRow(
      'Valor da Penalidade por No-Show',
      _formatFine((config['penalty_amount_cents'] as num?)?.toInt() ?? 0),
    ),
    'REQUIRED_EVIDENCE' => _LockedRow(
      'Evidências Obrigatórias',
      (config['types'] as List?)?.join(', ') ?? 'Nenhuma',
    ),
    _ => _LockedRow(
      'Configuração',
      config.entries.map((e) => '${e.key}: ${e.value}').join(', '),
    ),
  };
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
