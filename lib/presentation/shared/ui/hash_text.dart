import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Renders a hash, ID, or secret string with middle-ellipsis truncation,
/// a tooltip showing the full value, and an optional copy button.
///
/// When [masked] is true, displays `first8…last8` and provides a toggle
/// to reveal the full value — suitable for HMAC and signing secrets
/// (shoulder-surf protection).
///
/// **WASM-CONTEXT-LEAK:** [ScaffoldMessengerState] is captured synchronously
/// before the async [Clipboard.setData] call. No `if (mounted)` after await.
class HashText extends StatefulWidget {
  const HashText({
    super.key,
    required this.value,
    this.masked = false,
    this.showCopyButton = true,
    this.style,
  });

  /// The full string to display / copy.
  final String value;

  /// When true, hides the value as `first8…last8` until the user reveals it.
  final bool masked;

  /// Whether to show the clipboard copy icon button.
  final bool showCopyButton;

  /// Override text style. Defaults to [VeraProbTypography.mono].
  final TextStyle? style;

  @override
  State<HashText> createState() => _HashTextState();
}

class _HashTextState extends State<HashText> {
  bool _revealed = false;

  String get _displayValue {
    if (!widget.masked || _revealed) return widget.value;
    return _maskValue(widget.value);
  }

  static String _maskValue(String value) {
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}…${value.substring(value.length - 8)}';
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    // Capture messenger BEFORE await — WASM-CONTEXT-LEAK prevention
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: widget.value));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Copiado para a área de transferência.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = widget.style ?? VeraProbTypography.mono;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _buildText(effectiveStyle)),
        if (widget.masked) _buildRevealButton(),
        if (widget.showCopyButton) _buildCopyButton(context),
      ],
    );
  }

  Widget _buildText(TextStyle style) {
    return Tooltip(
      message: widget.value,
      child: Text(
        _displayValue,
        style: style,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Widget _buildRevealButton() {
    return Tooltip(
      message: _revealed ? 'Ocultar' : 'Revelar',
      child: IconButton(
        key: ValueKey('hash_text_reveal_${widget.value.hashCode}'),
        icon: Icon(
          _revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 16,
          color: VeraProbColors.textSecondary,
        ),
        onPressed: () => setState(() => _revealed = !_revealed),
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
    );
  }

  Widget _buildCopyButton(BuildContext context) {
    return Tooltip(
      message: 'Copiar',
      child: IconButton(
        key: ValueKey('hash_text_copy_${widget.value.hashCode}'),
        icon: const Icon(
          Icons.copy_outlined,
          size: 16,
          color: VeraProbColors.textSecondary,
        ),
        onPressed: () => _copyToClipboard(context),
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
    );
  }
}
