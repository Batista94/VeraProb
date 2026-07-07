import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/justification/submit_justification_command.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/presentation/shared/ui/evidence_validation_checklist_widget.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/justification_providers.dart';

/// Overlay dialog for submitting a contractor justification.
///
/// Two modes:
/// - **Operator path** (token == null): [callerRole] comes from JWT, all fields
///   editable including [contractId] and [setId].
/// - **Pre-filled path** (contractId + setId provided by SLA drawer): fields
///   are pre-filled but still editable.
///
/// Evidence files are SHA-256 hashed client-side (INV-9) via
/// [JustificationFileService] and uploaded to Supabase Storage.
/// File size guard: ≤ 10 MB per file (enforced by [JustificationFileService]).
/// INV-24: opened as an overlay modal.
class JustificationSubmissionForm extends ConsumerStatefulWidget {
  final String? contractId;
  final String? setId;
  final JustificationSubmissionToken? token;

  const JustificationSubmissionForm({
    super.key,
    this.contractId,
    this.setId,
    this.token,
  });

  @override
  ConsumerState<JustificationSubmissionForm> createState() =>
      _JustificationSubmissionFormState();
}

class _JustificationSubmissionFormState
    extends ConsumerState<JustificationSubmissionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _contractIdCtrl;
  late final TextEditingController _setIdCtrl;
  final _descriptionCtrl = TextEditingController();

  JustificationCategory _category = JustificationCategory.mechanical;
  final List<({String name, Uint8List bytes, String hash})> _files = [];
  bool _submitting = false;
  String? _error;
  final List<EvidenceValidationStep> _validationSteps = [];

  void _initValidationSteps() {
    _validationSteps
      ..clear()
      ..addAll(const [
        EvidenceValidationStep(
          kind: EvidenceValidationStepKind.transfer,
          status: EvidenceValidationStatus.pending,
        ),
        EvidenceValidationStep(
          kind: EvidenceValidationStepKind.digitalIdentity,
          status: EvidenceValidationStatus.pending,
        ),
        EvidenceValidationStep(
          kind: EvidenceValidationStepKind.probabilisticAudit,
          status: EvidenceValidationStatus.pending,
        ),
      ]);
  }

  void _updateStep(
    EvidenceValidationStepKind kind,
    EvidenceValidationStatus status, {
    Object? error,
  }) {
    final idx = _validationSteps.indexWhere((s) => s.kind == kind);
    if (idx == -1) return;
    _validationSteps[idx] = EvidenceValidationStep(
      kind: kind,
      status: status,
      error: error,
    );
  }

  @override
  void initState() {
    super.initState();
    _contractIdCtrl = TextEditingController(text: widget.contractId ?? '');
    _setIdCtrl = TextEditingController(text: widget.setId ?? '');
  }

  @override
  void dispose() {
    _contractIdCtrl.dispose();
    _setIdCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: VeraProbColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: VeraProbRadii.xlAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FormHeader(onClose: () => Navigator.pop(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: VeraProbColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      if (widget.token == null) ...[
                        TextFormField(
                          controller: _contractIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ID do Contrato',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _setIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'SET ID',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        _ReadOnlyField(
                          label: 'Contrato',
                          value: widget.token!.contractId,
                        ),
                        const SizedBox(height: 8),
                        _ReadOnlyField(
                          label: 'SET ID',
                          value: widget.token!.setId,
                        ),
                        const SizedBox(height: 16),
                      ],
                      DropdownButtonFormField<JustificationCategory>(
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          border: OutlineInputBorder(),
                        ),
                        items: JustificationCategory.values
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(_categoryLabel(c)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _category = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Descrição (mín. 20 caracteres)',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if ((v ?? '').trim().length < 20) {
                            return 'A descrição deve ter pelo menos 20 caracteres.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _EvidenceSection(
                        files: _files,
                        onPickFiles: _pickFiles,
                        onRemove: (i) => setState(() => _files.removeAt(i)),
                      ),
                      if (_validationSteps.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        EvidenceValidationChecklistWidget(
                          steps: _validationSteps,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  // ACCENT-FILL-CONTRAST: dark fg on fill.
                  style: FilledButton.styleFrom(
                    backgroundColor: VeraProbColors.primary,
                    foregroundColor: VeraProbColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enviar Justificativa'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(justificationFileServiceProvider);
    final result = await service.pickFiles();

    for (final name in result.oversized) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('$name: arquivo maior que 10 MB. Ignorado.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }

    for (final f in result.picked) {
      // INV-9: SHA-256 client-side before upload
      final hash = sha256.convert(f.bytes).toString();
      setState(() => _files.add((name: f.name, bytes: f.bytes, hash: hash)));
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final hasFiles = _files.isNotEmpty;

    setState(() {
      _submitting = true;
      _error = null;
      if (hasFiles) {
        _initValidationSteps();
        _updateStep(
          EvidenceValidationStepKind.digitalIdentity,
          EvidenceValidationStatus.completed,
        );
      } else {
        _validationSteps.clear();
      }
    });

    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final userId = ref.read(currentOperatorIdProvider);
      final role = ref.read(currentUserRoleProvider);
      final session = ref.read(authStateProvider).value?.session;
      final email = session?.user.email ?? '';
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      if (orgId == null) {
        if (mounted) setState(() => _error = 'Organização não encontrada.');
        return;
      }

      final contractId =
          widget.token?.contractId ?? _contractIdCtrl.text.trim();
      final setId = widget.token?.setId ?? _setIdCtrl.text.trim();
      final tokenId = widget.token?.id;

      // Upload evidence files and collect hashes + scan URLs.
      final hashes = <String>[];
      final evidenceUrls = <String>[];
      if (hasFiles) {
        setState(
          () => _updateStep(
            EvidenceValidationStepKind.transfer,
            EvidenceValidationStatus.running,
          ),
        );
        final storage = ref.read(justificationStorageServiceProvider);
        final fileService = ref.read(justificationFileServiceProvider);
        try {
          for (final f in _files) {
            final String storagePath;
            if (widget.token != null) {
              final result = await storage.getSignedUploadUrl(
                justificationToken: widget.token!.token,
                fileName: f.name,
              );
              await fileService.uploadPut(result.url, f.bytes);
              storagePath = result.storagePath;
            } else {
              storagePath = await storage.uploadAuthenticated(
                organizationId: orgId,
                justificationId: 'pending',
                fileName: f.name,
                bytes: f.bytes,
              );
            }
            hashes.add(f.hash);
            evidenceUrls.add(await storage.getScanUrl(storagePath));
          }
          if (mounted) {
            setState(
              () => _updateStep(
                EvidenceValidationStepKind.transfer,
                EvidenceValidationStatus.completed,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            setState(
              () => _updateStep(
                EvidenceValidationStepKind.transfer,
                EvidenceValidationStatus.failed,
                error: e,
              ),
            );
          }
          rethrow;
        }

        setState(
          () => _updateStep(
            EvidenceValidationStepKind.probabilisticAudit,
            EvidenceValidationStatus.running,
          ),
        );
      }

      try {
        await ref
            .read(submitJustificationHandlerProvider)
            .handle(
              SubmitJustificationCommand(
                organizationId: orgId,
                contractId: contractId,
                setId: setId,
                planVersion: 0,
                category: _category.dbValue,
                description: _descriptionCtrl.text.trim(),
                callerRole: widget.token != null ? null : role,
                callerUserId: widget.token != null ? null : userId,
                callerEmail: widget.token != null ? null : email,
                submittedByTokenId: tokenId,
                evidenceHashes: hashes,
                evidenceUrls: evidenceUrls,
                sessionId: sessionId,
              ),
            );
        if (hasFiles && mounted) {
          setState(
            () => _updateStep(
              EvidenceValidationStepKind.probabilisticAudit,
              EvidenceValidationStatus.completed,
            ),
          );
        }
      } catch (e) {
        if (hasFiles && mounted) {
          setState(
            () => _updateStep(
              EvidenceValidationStepKind.probabilisticAudit,
              EvidenceValidationStatus.failed,
              error: e,
            ),
          );
        }
        rethrow;
      }

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Justificativa enviada com sucesso.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Falha ao enviar justificativa. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _categoryLabel(JustificationCategory c) {
    return switch (c) {
      JustificationCategory.mechanical => 'Mecânico',
      JustificationCategory.forceMajeure => 'Força Maior',
      JustificationCategory.traffic => 'Trânsito',
      JustificationCategory.routeDeviation => 'Desvio de Rota',
      JustificationCategory.communication => 'Comunicação',
      JustificationCategory.other => 'Outro',
    };
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _FormHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _FormHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: VeraProbColors.border.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Nova Justificativa', style: VeraProbTypography.sectionTitle),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: VeraProbTypography.caption.copyWith(
            color: VeraProbColors.textSecondary,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: VeraProbTypography.bodyMedium),
      ],
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  final List<({String name, Uint8List bytes, String hash})> files;
  final VoidCallback onPickFiles;
  final ValueChanged<int> onRemove;

  const _EvidenceSection({
    required this.files,
    required this.onPickFiles,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('EVIDÊNCIAS (opcional)', style: VeraProbTypography.caption),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onPickFiles,
          icon: const Icon(Icons.attach_file, size: 16),
          label: const Text('Anexar Arquivo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: VeraProbColors.textSecondary,
            side: const BorderSide(color: VeraProbColors.border),
          ),
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...files.asMap().entries.map(
            (e) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined, size: 18),
              title: Text(e.value.name, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${e.value.hash.substring(0, 16)}...',
                style: VeraProbTypography.mono(
                  size: 11,
                  color: VeraProbColors.textDisabled,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => onRemove(e.key),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        const Text(
          'Máx. 10 MB por arquivo. Imagens, PDF ou ZIP.',
          style: TextStyle(fontSize: 11, color: VeraProbColors.textDisabled),
        ),
      ],
    );
  }
}
