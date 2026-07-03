import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Chip-based input for email domain whitelists.
///
/// Validates, normalizes (lowercase + trim), and deduplicates domains.
/// Notifies [onChanged] with the full list on every mutation.
class DomainChipInput extends StatefulWidget {
  final List<String> initialDomains;
  final ValueChanged<List<String>> onChanged;
  final String? labelText;
  final String? hintText;

  const DomainChipInput({
    super.key,
    required this.initialDomains,
    required this.onChanged,
    this.labelText,
    this.hintText,
  });

  @override
  State<DomainChipInput> createState() => _DomainChipInputState();
}

class _DomainChipInputState extends State<DomainChipInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late List<String> _domains;
  String? _inputError;

  static final _domainRegex = RegExp(r'^[a-z0-9][a-z0-9\-]*(\.[a-z0-9\-]+)+$');

  @override
  void initState() {
    super.initState();
    _domains = List<String>.from(widget.initialDomains);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? _validateDomain(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return 'Informe um domínio';
    if (value.contains('://')) return 'Não use URL completa';
    if (value.contains('@')) return 'Não inclua o símbolo @';
    if (value.contains(' ')) return 'Sem espaços';
    if (!_domainRegex.hasMatch(value)) {
      return 'Formato inválido (ex: empresa.com.br)';
    }
    if (_domains.contains(value)) return 'Domínio já adicionado';
    return null;
  }

  void _addDomain() {
    final error = _validateDomain(_controller.text);
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    final normalized = _controller.text.trim().toLowerCase();
    setState(() {
      _domains = {..._domains, normalized}.toList();
      _inputError = null;
      _controller.clear();
    });
    widget.onChanged(_domains);
  }

  void _removeDomain(String domain) {
    setState(() => _domains = _domains.where((d) => d != domain).toList());
    widget.onChanged(_domains);
  }

  bool get _canAdd => _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Text(widget.labelText!, style: VeraProbTypography.sectionTitle),
          const SizedBox(height: VeraProbSpacing.xs),
        ],
        Container(
          decoration: BoxDecoration(
            color: VeraProbColors.surface,
            borderRadius: VeraProbRadii.lgAll,
            border: Border.all(
              color: _inputError != null
                  ? VeraProbColors.error
                  : VeraProbColors.border,
            ),
          ),
          padding: const EdgeInsets.all(VeraProbSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_domains.isNotEmpty) ...[
                Wrap(
                  spacing: VeraProbSpacing.xs,
                  runSpacing: VeraProbSpacing.xs,
                  children: _domains
                      .map(
                        (d) => InputChip(
                          label: Text(
                            d,
                            style: VeraProbTypography.bodySmall.copyWith(
                              color: VeraProbColors.textPrimary,
                            ),
                          ),
                          backgroundColor: VeraProbColors.surfaceElevated,
                          deleteIcon: const Icon(Icons.cancel, size: 18),
                          deleteIconColor: VeraProbColors.textSecondary,
                          onDeleted: () => _removeDomain(d),
                          shape: const RoundedRectangleBorder(
                            borderRadius: VeraProbRadii.mdAll,
                            side: BorderSide(color: VeraProbColors.border),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: VeraProbSpacing.sm),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: VeraProbTypography.bodyMedium,
                      decoration: InputDecoration(
                        hintText: widget.hintText ?? 'ex: empresa.com.br',
                        hintStyle: VeraProbTypography.bodySmall,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: VeraProbSpacing.xs,
                          vertical: VeraProbSpacing.xs,
                        ),
                      ),
                      onChanged: (_) => setState(() => _inputError = null),
                      onSubmitted: (_) => _addDomain(),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(width: VeraProbSpacing.xs),
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, child) => IconButton(
                      icon: const Icon(Icons.add),
                      color: _canAdd
                          ? VeraProbColors.primary
                          : VeraProbColors.textDisabled,
                      onPressed: _canAdd ? _addDomain : null,
                      tooltip: 'Adicionar domínio',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_inputError != null) ...[
          const SizedBox(height: VeraProbSpacing.xs),
          Text(
            _inputError!,
            style: VeraProbTypography.bodySmall.copyWith(
              color: VeraProbColors.error,
            ),
          ),
        ],
      ],
    );
  }
}
