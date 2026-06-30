import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_submission_notifier.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';

class EvidenceDropzone extends StatefulWidget {
  final PortalSubmissionState state;
  final void Function(StagedFile) onFileStaged;
  final VoidCallback onFileCleared;

  const EvidenceDropzone({
    super.key,
    required this.state,
    required this.onFileStaged,
    required this.onFileCleared,
  });

  @override
  State<EvidenceDropzone> createState() => _EvidenceDropzoneState();
}

class _EvidenceDropzoneState extends State<EvidenceDropzone> {
  String? _inlineError;

  Future<void> _pickFile() async {
    setState(() {
      _inlineError = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;

        if (bytes == null) {
          throw const PortalDisputeException(
            'Erro ao ler conteúdo do arquivo.',
          );
        }

        final stagedFile = StagedFile(
          name: file.name,
          sizeBytes: file.size,
          mimeType: _getMimeType(file.extension),
          bytes: bytes,
        );

        // Validation happens in the Notifier's stageFile method,
        // which throws IntegrityException if invalid.
        widget.onFileStaged(stagedFile);
      }
    } catch (e) {
      setState(() => _inlineError = _humanizeFilePickError(e));
    }
  }

  String _humanizeFilePickError(Object e) {
    try {
      final msg = (e as dynamic).message;
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {}
    return 'Não foi possível processar o arquivo. Verifique o formato e tente novamente.';
  }

  String _getMimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUploading = widget.state is PortalSubmissionUploading;
    final bool isHashing = widget.state is PortalSubmissionHashing;
    final bool isRetrying = widget.state is PortalSubmissionRetrying;
    final bool isBusy = isUploading || isHashing || isRetrying;

    StagedFile? currentFile;
    if (widget.state is PortalSubmissionStaging) {
      currentFile = (widget.state as PortalSubmissionStaging).file;
    } else if (widget.state is PortalSubmissionError) {
      currentFile = (widget.state as PortalSubmissionError).recoverable.file;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Evidência Complementar (Opcional)',
          style: VeraProbTypography.fieldLabel,
        ),
        const SizedBox(height: VeraProbSpacing.xs),
        if (currentFile != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: VeraProbSpacing.md,
              vertical: VeraProbSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VeraProbColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_file, color: VeraProbColors.primary),
                const SizedBox(width: VeraProbSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentFile.name,
                        style: VeraProbTypography.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${(currentFile.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                        style: VeraProbTypography.caption,
                      ),
                    ],
                  ),
                ),
                if (!isBusy)
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: VeraProbColors.textSecondary,
                    ),
                    onPressed: widget.onFileCleared,
                    tooltip: 'Remover anexo',
                  ),
              ],
            ),
          ),
          if (isBusy) ...[
            const SizedBox(height: VeraProbSpacing.xs),
            const LinearProgressIndicator(
              backgroundColor: VeraProbColors.surfaceElevated,
              color: VeraProbColors.primary,
            ),
            const SizedBox(height: VeraProbSpacing.xs),
            Text(
              isHashing ? 'Verificando integridade...' : 'Enviando...',
              style: VeraProbTypography.caption.copyWith(
                color: VeraProbColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ] else ...[
          InkWell(
            onTap: isBusy ? null : _pickFile,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: VeraProbSpacing.sectionPadding,
              decoration: BoxDecoration(
                color: isBusy
                    ? VeraProbColors.surface
                    : VeraProbColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _inlineError != null
                      ? VeraProbColors.error
                      : VeraProbColors.border,
                  style:
                      BorderStyle.none, // We'd use dashed border realistically
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.upload_file,
                      color: _inlineError != null
                          ? VeraProbColors.error
                          : VeraProbColors.textSecondary,
                      size: 32,
                    ),
                    const SizedBox(height: VeraProbSpacing.sm),
                    Text(
                      'Toque para anexar evidência (máx 10MB)',
                      style: VeraProbTypography.bodyMedium.copyWith(
                        color: _inlineError != null
                            ? VeraProbColors.error
                            : VeraProbColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Formatos: PDF, PNG, JPG',
                      style: VeraProbTypography.caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isBusy) ...[
            const SizedBox(height: VeraProbSpacing.xs),
            const LinearProgressIndicator(
              backgroundColor: VeraProbColors.surfaceElevated,
              color: VeraProbColors.primary,
            ),
          ],
        ],
        if (_inlineError != null) ...[
          const SizedBox(height: VeraProbSpacing.xs),
          Text(
            _inlineError!,
            style: VeraProbTypography.caption.copyWith(
              color: VeraProbColors.error,
            ),
          ),
        ],
      ],
    );
  }
}
