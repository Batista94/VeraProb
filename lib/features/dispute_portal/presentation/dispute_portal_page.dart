import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';

/// Public, tokenized dispute portal for an external carrier (no Supabase auth).
///
/// Reached via `/portal/dispute?token=<uuid>`. Three branches driven by the
/// served snapshot status:
///   • always — review the sealed evidence the system holds;
///   • `disputed` — submit counter-evidence (browser → quarantine → finalize);
///   • `applied`  — "De Acordo": accept the penalty (hash-bound, INV-9).
///
/// Lesson 8: the ScaffoldMessenger is captured before the first `await`, and an
/// `_isSaving` guard prevents the ClickDebouncer double-tap loop (CT02).
class DisputePortalPage extends ConsumerStatefulWidget {
  final String token;
  const DisputePortalPage({super.key, required this.token});

  @override
  ConsumerState<DisputePortalPage> createState() => _DisputePortalPageState();
}

class _DisputePortalPageState extends ConsumerState<DisputePortalPage> {
  static const int _kMaxBytes = 10 * 1024 * 1024;
  static const Map<String, String> _allowedExtensions = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'pdf': 'application/pdf',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'webp': 'image/webp',
  };

  PortalSnapshot? _snapshot;
  bool _loading = true;
  bool _isSaving = false;
  bool _acknowledged = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await ref
          .read(portalDisputeGatewayProvider)
          .read(widget.token);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _snapshot = snap;
      });
    } on PortalDisputeException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Link inválido ou expirado.';
      });
    }
  }

  Future<void> _submitCounterEvidence() async {
    if (_isSaving) return;
    final messenger = ScaffoldMessenger.of(context);
    final gateway = ref.read(portalDisputeGatewayProvider);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions.keys.toList(),
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    final mime = _allowedExtensions[(file.extension ?? '').toLowerCase()];

    if (mime == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Tipo não permitido. Use JPG, PNG, PDF, HEIC ou WEBP.'),
        ),
      );
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Arquivo vazio ou ilegível.')),
      );
      return;
    }
    if (bytes.length > _kMaxBytes) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Arquivo excede 10 MB.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final outcome = await gateway.submitEvidence(
        token: widget.token,
        fileName: file.name,
        mimeType: mime,
        bytes: bytes,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_outcomeMessage(outcome))));
      if (outcome == PortalSubmissionOutcome.pendingAudit) {
        await _load();
      }
    } on PortalDisputeException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _acknowledge() async {
    if (_isSaving || _snapshot == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final gateway = ref.read(portalDisputeGatewayProvider);
    setState(() => _isSaving = true);
    try {
      await gateway.acknowledge(
        token: widget.token,
        snapshotHash: _snapshot!.snapshotHash,
      );
      if (!mounted) return;
      setState(() => _acknowledged = true);
    } on PortalDisputeException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static String _outcomeMessage(PortalSubmissionOutcome o) => switch (o) {
    PortalSubmissionOutcome.pendingAudit =>
      'Contraprova enviada. Aguardando análise do auditor.',
    PortalSubmissionOutcome.hashMismatch =>
      'O arquivo foi alterado durante o envio. Tente novamente.',
    PortalSubmissionOutcome.mimeMismatch =>
      'O conteúdo do arquivo não corresponde ao tipo informado.',
    PortalSubmissionOutcome.rejected => 'Arquivo recusado.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Validando link...',
            style: TextStyle(color: VeraProbColors.textSecondary),
          ),
        ],
      );
    }
    if (_errorMessage != null) {
      return _PortalCard(
        icon: Icons.error_outline,
        color: VeraProbColors.error,
        title: 'Link Inválido',
        message: _errorMessage!,
      );
    }
    if (_acknowledged) {
      return const _PortalCard(
        icon: Icons.verified_outlined,
        color: VeraProbColors.success,
        title: 'Penalidade Aceita',
        message:
            'Seu aceite foi registrado de forma definitiva e auditável. '
            'Obrigado.',
      );
    }
    final snap = _snapshot;
    if (snap == null) return const SizedBox.shrink();
    return _LoadedView(
      snapshot: snap,
      isSaving: _isSaving,
      onSubmit: _submitCounterEvidence,
      onAcknowledge: _acknowledge,
    );
  }
}

class _LoadedView extends StatelessWidget {
  final PortalSnapshot snapshot;
  final bool isSaving;
  final VoidCallback onSubmit;
  final VoidCallback onAcknowledge;

  const _LoadedView({
    required this.snapshot,
    required this.isSaving,
    required this.onSubmit,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.gavel_outlined, color: VeraProbColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Portal de Disputa',
                style: VeraProbTypography.sectionTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _VerdictSummary(snapshot: snapshot),
        const SizedBox(height: 16),
        _EvidenceList(items: snapshot.evidence),
        const SizedBox(height: 24),
        if (snapshot.isDisputed)
          _SubmitBranch(isSaving: isSaving, onSubmit: onSubmit),
        if (snapshot.isApplied)
          _DeAcordoBranch(
            snapshot: snapshot,
            isSaving: isSaving,
            onAcknowledge: onAcknowledge,
          ),
      ],
    );
  }
}

class _VerdictSummary extends StatelessWidget {
  final PortalSnapshot snapshot;
  const _VerdictSummary({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: VeraProbColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.ruleType ?? 'Ocorrência',
            style: VeraProbTypography.sectionTitle,
          ),
          if (snapshot.description != null) ...[
            const SizedBox(height: 6),
            Text(
              snapshot.description!,
              style: const TextStyle(color: VeraProbColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceList extends StatelessWidget {
  final List<PortalEvidenceItem> items;
  const _EvidenceList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Evidências (${items.length})',
          style: const TextStyle(
            color: VeraProbColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text(
            'Nenhuma evidência anexada.',
            style: TextStyle(color: VeraProbColors.textSecondary),
          )
        else
          ...items.map(
            (e) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.description_outlined,
                color: VeraProbColors.primary,
              ),
              title: Text(
                e.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                'SHA-256 ${e.sha256Hash.substring(0, e.sha256Hash.length >= 12 ? 12 : e.sha256Hash.length)}…',
                style: const TextStyle(color: VeraProbColors.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}

class _SubmitBranch extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onSubmit;
  const _SubmitBranch({required this.isSaving, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contestar — enviar contraprova',
          style: VeraProbTypography.sectionTitle,
        ),
        const SizedBox(height: 8),
        const Text(
          'Envie um documento (JPG, PNG, PDF, HEIC ou WEBP, até 10 MB). '
          'O arquivo é verificado criptograficamente no servidor.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: isSaving ? null : onSubmit,
          icon: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file_outlined),
          label: Text(isSaving ? 'Enviando...' : 'Selecionar e enviar'),
        ),
      ],
    );
  }
}

class _DeAcordoBranch extends StatelessWidget {
  final PortalSnapshot snapshot;
  final bool isSaving;
  final VoidCallback onAcknowledge;

  const _DeAcordoBranch({
    required this.snapshot,
    required this.isSaving,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: VeraProbColors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'De Acordo — aceitar penalidade',
            style: VeraProbTypography.sectionTitle,
          ),
          const SizedBox(height: 8),
          const Text(
            'Ao confirmar, você aceita formalmente a penalidade conforme '
            'apresentada acima. O aceite é definitivo e auditável.',
            style: TextStyle(color: VeraProbColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SelectableText(
            'Hash do registro: ${snapshot.snapshotHash}',
            style: const TextStyle(
              color: VeraProbColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.success,
            ),
            onPressed: isSaving ? null : onAcknowledge,
            icon: isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(isSaving ? 'Registrando...' : 'Confirmar De Acordo'),
          ),
        ],
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _PortalCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 16),
          Text(
            title,
            style: VeraProbTypography.sectionTitle.copyWith(color: color),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VeraProbColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
