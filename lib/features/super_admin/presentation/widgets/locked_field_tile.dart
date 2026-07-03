import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

const Color _kLockedFieldBorder = Color(0xFF2A3A5C);

/// A read-only tile that displays an immutable field with a lock icon,
/// tooltip, hover effect, and optional click-to-copy.
///
/// Used in the "Identidade Imutável" section of [TenantConfigTab] to
/// render Core Identity fields (Slug, CNPJ, Data de Criação) that
/// cannot be edited after provisioning (INV-1).
///
/// The value is rendered with [SelectableText] to allow partial text
/// selection for audit scenarios — no blinking cursor, no virtual
/// keyboard on mobile.
///
/// **No** [TextField], [EditableText], or any editable input widget
/// is used in this widget.
class LockedFieldTile extends StatefulWidget {
  /// Label displayed above the value (e.g. "Slug", "CNPJ").
  final String label;

  /// The value to display. When `null`, [placeholder] is shown instead.
  final String? value;

  /// Text shown when [value] is `null`.
  final String placeholder;

  /// Tooltip text displayed on hover over the lock icon.
  final String tooltipText;

  /// Callback executed when the tile is tapped.
  /// When `null`, the tile shows a basic cursor and tap is a no-op.
  final VoidCallback? onCopy;

  const LockedFieldTile({
    super.key,
    required this.label,
    this.value,
    this.placeholder = 'Não informado',
    this.tooltipText =
        'Identidade Core imutável para garantir a integridade da '
        'Cadeia de Custódia (INV-1).',
    this.onCopy,
  });

  @override
  State<LockedFieldTile> createState() => _LockedFieldTileState();
}

class _LockedFieldTileState extends State<LockedFieldTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onCopy != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onCopy,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? VeraProbColors.surface.withValues(alpha: 0.05)
                : VeraProbColors.surface,
            border: Border.all(color: _kLockedFieldBorder),
            borderRadius: VeraProbRadii.lgAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Label row with lock icon ──
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: VeraProbTypography.fieldLabel,
                    ),
                  ),
                  Tooltip(
                    message: widget.tooltipText,
                    child: const Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: VeraProbColors.textDisabled,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // ── Value or placeholder ──
              if (widget.value != null)
                Opacity(
                  opacity: 0.7,
                  child: SelectableText(
                    widget.value!,
                    style: VeraProbTypography.dataValue,
                  ),
                )
              else
                Text(widget.placeholder, style: VeraProbTypography.caption),
            ],
          ),
        ),
      ),
    );
  }
}
