import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:veraprob/core/theme/app_theme.dart';

class InvitationActionButtons extends StatelessWidget {
  final String? token;
  final bool isDisabled;
  final VoidCallback? onCopyLink;
  final VoidCallback onResend;
  final VoidCallback onRevoke;

  const InvitationActionButtons({
    super.key,
    this.token,
    this.isDisabled = false,
    this.onCopyLink,
    required this.onResend,
    required this.onRevoke,
  });

  void _handleCopyLink(BuildContext context) {
    if (onCopyLink != null) {
      onCopyLink!();
      return;
    }

    if (token == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final baseUri = Uri.base;
    final origin = (baseUri.scheme == 'http' || baseUri.scheme == 'https')
        ? baseUri.origin
        : 'http://localhost:3000';
    final link = '$origin/accept-invite?token=$token';

    Clipboard.setData(ClipboardData(text: link));
    messenger.showSnackBar(
      const SnackBar(content: Text('Link de convite copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (token != null || onCopyLink != null)
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 20),
            tooltip: 'Copiar link de convite',
            color: VeraProbColors.textSecondary,
            onPressed: isDisabled ? null : () => _handleCopyLink(context),
          ),
        IconButton(
          icon: const Icon(Icons.send_outlined, size: 20),
          tooltip: 'Reenviar Convite',
          color: VeraProbColors.textSecondary,
          onPressed: isDisabled ? null : onResend,
        ),
        IconButton(
          icon: const Icon(Icons.cancel_outlined, size: 20),
          tooltip: 'Revogar Convite',
          color: VeraProbColors.error,
          onPressed: isDisabled ? null : onRevoke,
        ),
      ],
    );
  }
}
