import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.secret));
    
    // Configura o TTL (Time-To-Live) da Clipboard (60 segundos)
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = Timer(const Duration(seconds: 60), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado! O segredo sumirá da área de transferência em 60s.'),
        backgroundColor: Colors.amber, // Cor de risco UX-Ops
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Slate/Zinc palette (Industrial Deep)
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Segredo HMAC Gerado',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Copie agora. Por segurança, não será exibido novamente.',
            style: TextStyle(color: Colors.amber),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.secret,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white),
                  onPressed: _copyToClipboard,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar e Destruir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
