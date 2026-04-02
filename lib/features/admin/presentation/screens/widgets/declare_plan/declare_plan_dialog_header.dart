import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

class DeclarePlanDialogHeader extends StatelessWidget {
  final String contractName;
  final int confirmedShiftsCount;
  final VoidCallback onClose;

  const DeclarePlanDialogHeader({
    super.key,
    required this.contractName,
    required this.confirmedShiftsCount,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24).copyWith(bottom: 0),
      child: Row(
        children: [
          const Icon(Icons.playlist_add_check_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configurar Padrão de Fretamento (B2B)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  contractName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (confirmedShiftsCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: VeraProbColors.info.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: VeraProbColors.info.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '${confirmedShiftsCount + 1} turnos',
                style: const TextStyle(
                  fontSize: 11,
                  color: VeraProbColors.info,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
