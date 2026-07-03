import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:veraprob/core/theme/app_theme.dart';

class HmacSecretModal extends StatefulWidget {
  final String secret;

  const HmacSecretModal({super.key, required this.secret});

  @override
  State<HmacSecretModal> createState() => _HmacSecretModalState();
}

class _HmacSecretModalState extends State<HmacSecretModal> {
  Timer? _clipboardClearTimer;

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: widget.secret));

    // Configura o TTL (Time-To-Live) da Clipboard (60 segundos)
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = Timer(const Duration(seconds: 60), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });

    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Copiado! O segredo sumirá da área de transferência em 60s.',
        ),
        backgroundColor: VeraProbColors.warning, // Cor de risco UX-Ops
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VeraProbColors.surface, // Slate/Zinc palette (Industrial Deep)
        borderRadius: VeraProbRadii.lgAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: VeraProbColors.warning,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Segredo HMAC Gerado',
            style: VeraProbTypography.sectionTitle.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            'Copie agora. Por segurança, não será exibido novamente.',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.warning,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            color: VeraProbColors.surfaceElevated,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.secret,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      color: VeraProbColors.textPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.copy,
                    color: VeraProbColors.textPrimary,
                  ),
                  onPressed: _copyToClipboard,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: VeraProbColors.error,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Fechar e Destruir',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
