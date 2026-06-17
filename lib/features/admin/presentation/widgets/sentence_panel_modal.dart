import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/domain_error_text.dart';
import 'dispute_reason_code_dropdown.dart';

class SentencePanelModal extends StatefulWidget {
  final String title;
  final String actionLabel;
  final Color actionColor;
  final bool showSlaWarning;
  final bool isAccept;
  final bool requireTextAlways;
  final Future<void> Function(String reasonCode, String reasonText) onConfirm;

  const SentencePanelModal({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.actionColor,
    required this.showSlaWarning,
    required this.isAccept,
    required this.requireTextAlways,
    required this.onConfirm,
  });

  @override
  State<SentencePanelModal> createState() => _SentencePanelModalState();
}

class _SentencePanelModalState extends State<SentencePanelModal> {
  String? _selectedCode;
  final _textController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _assumedRisk = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_isLoading) return false;
    if (widget.showSlaWarning && !_assumedRisk) return false;
    if (_selectedCode == null) return false;
    if (widget.requireTextAlways || _selectedCode == 'OTHER') {
      return _textController.text.trim().length >= 10;
    }
    return true;
  }

  Future<void> _handleConfirm() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.onConfirm(_selectedCode!, _textController.text.trim());
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = humanizeDomainError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool requireText =
        widget.requireTextAlways || _selectedCode == 'OTHER';

    return Dialog(
      backgroundColor: VeraProbColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: VeraProbColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.showSlaWarning) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VeraProbColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: VeraProbColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: VeraProbColors.warning,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Atenção: Transportador ainda no prazo de SLA.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: VeraProbColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _assumedRisk,
                              onChanged: _isLoading
                                  ? null
                                  : (val) {
                                      setState(() {
                                        _assumedRisk = val ?? false;
                                      });
                                    },
                              activeColor: VeraProbColors.warning,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Assumo o risco de julgar sem aguardar a defesa.',
                              style: TextStyle(
                                fontSize: 12,
                                color: VeraProbColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              DisputeReasonCodeDropdown(
                enabled: !_isLoading,
                selectedCode: _selectedCode,
                onChanged: _isLoading
                    ? (v) {}
                    : (code) {
                        setState(() {
                          _selectedCode = code;
                        });
                      },
                label: widget.isAccept
                    ? 'Motivo da anulação (taxonomia)'
                    : 'Motivo da manutenção (taxonomia)',
              ),
              const SizedBox(height: 16),
              if (!widget.isAccept) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 13,
                      color: VeraProbColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Manter a multa sela o hash da evidência — veredito imutável (INV-21).',
                        style: VeraProbTypography.caption.copyWith(
                          color: VeraProbColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                key: const ValueKey('sentence-comment-field'),
                controller: _textController,
                enabled: !_isLoading,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: requireText
                      ? 'Comentário obrigatório (mínimo 10 caracteres)'
                      : 'Descreva o motivo (opcional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: VeraProbColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: VeraProbColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: VeraProbColors.error,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: VeraProbColors.error,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: _canConfirm ? _handleConfirm : null,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: Text(widget.actionLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.actionColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
