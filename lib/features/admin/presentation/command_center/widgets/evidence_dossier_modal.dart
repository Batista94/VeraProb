import 'dart:developer' as dev;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/config/environment.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Full evidence photo dossier — shown via [showModalBottomSheet].
///
/// Renders up to 15 evidence thumbnails in a 3-column grid.
/// All images are fetched exclusively through secure-evidence-proxy (INV-26).
///
/// Usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (_) => EvidenceDossierModal(evidenceIds: ids),
/// );
/// ```
class EvidenceDossierModal extends ConsumerStatefulWidget {
  /// Full list of evidence IDs to display.
  final List<String> evidenceIds;

  /// Maximum items rendered in the grid.
  static const int _kMaxItems = 15;

  const EvidenceDossierModal({super.key, required this.evidenceIds});

  @override
  ConsumerState<EvidenceDossierModal> createState() =>
      _EvidenceDossierModalState();
}

class _EvidenceDossierModalState extends ConsumerState<EvidenceDossierModal> {
  int _loadedCount = 0;
  bool get _isLoading =>
      _loadedCount <
      widget.evidenceIds.take(EvidenceDossierModal._kMaxItems).length;

  @override
  Widget build(BuildContext context) {
    final accessToken = ref.watch(currentSessionIdProvider) ?? '';
    final items = widget.evidenceIds
        .take(EvidenceDossierModal._kMaxItems)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: VeraProbColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Progress indicator (INV-26: visual feedback during proxy download) ──
          if (_isLoading)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: VeraProbColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(VeraProbColors.primary),
            )
          else
            const SizedBox(height: 2),
          // ── Drag handle ──
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: VeraProbColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.photo_library_rounded,
                  color: VeraProbColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Dossiê Forense',
                  style: VeraProbTypography.sectionTitle.copyWith(
                    color: VeraProbColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: VeraProbColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.evidenceIds.length} FOTOS',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: VeraProbColors.primary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: VeraProbColors.textSecondary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const Divider(color: VeraProbColors.border, height: 16),
          // ── Grid ──
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final id = items[index];
                // INV-26: ALL images MUST go through secure-evidence-proxy
                final url =
                    '${EnvironmentConfig.supabaseUrl}/functions/v1/secure-evidence-proxy?evidence_id=$id'; // pr_scanner: ignore

                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    httpHeaders: {'Authorization': 'Bearer $accessToken'},
                    fit: BoxFit.cover,
                    placeholder: (ctx, _) => _Placeholder(),
                    errorWidget: (ctx, url, error) {
                      // INV-26: Log proxy errors for forensic debugging
                      dev.log(
                        '[EvidenceDossierModal] Proxy error for evidence_id=$id',
                        name: 'EvidenceDossierModal',
                        error: error,
                        level: 900, // WARNING
                      );
                      return _Placeholder();
                    },
                    imageBuilder: (context, imageProvider) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _loadedCount < items.length) {
                          setState(() => _loadedCount++);
                        }
                      });
                      return Image(image: imageProvider, fit: BoxFit.cover);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: VeraProbColors.surfaceElevated,
      child: const Icon(
        Icons.fingerprint_rounded,
        size: 24,
        color: VeraProbColors.textDisabled,
      ),
    );
  }
}
