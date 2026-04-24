import 'dart:developer' as dev;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/config/environment.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/shared/compliance_widgets.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_category_chip.dart';
import 'package:veraprob/features/admin/presentation/shared/forensic_audio_player.dart';
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

  /// Optional category map: evidenceId → category key.
  /// When provided, items are sorted by risk and a caption is shown.
  final Map<String, String?> categories;

  /// Optional MIME type map: evidenceId → mime_type string.
  /// When an entry starts with 'audio/', a [ForensicAudioPlayer] is rendered.
  final Map<String, String?> mimeTypes;

  /// Optional compliance result — when provided, shows [EvidenceComplianceChecklist]
  /// above the photo grid. Null = no checklist (backward compatible).
  final ActiveCompliance? compliance;

  /// Maximum items rendered in the grid.
  static const int _kMaxItems = 15;

  const EvidenceDossierModal({
    super.key,
    required this.evidenceIds,
    this.categories = const {},
    this.mimeTypes = const {},
    this.compliance,
  });

  @override
  ConsumerState<EvidenceDossierModal> createState() =>
      _EvidenceDossierModalState();
}

class _EvidenceDossierModalState extends ConsumerState<EvidenceDossierModal> {
  int _loadedCount = 0;
  bool get _isLoading =>
      _loadedCount <
      widget.evidenceIds.take(EvidenceDossierModal._kMaxItems).length;

  bool _isAudio(String id) =>
      widget.mimeTypes[id]?.startsWith('audio/') ?? false;

  String get _headerLabel {
    final audioCount = widget.evidenceIds.where(_isAudio).length;
    final photoCount = widget.evidenceIds.length - audioCount;
    if (audioCount == 0) return '$photoCount FOTOS';
    if (photoCount == 0) return '$audioCount ÁUDIOS';
    return '$photoCount FOTOS · $audioCount ÁUDIOS';
  }

  @override
  Widget build(BuildContext context) {
    final accessToken = ref.watch(currentSessionIdProvider) ?? '';
    // Sort by risk when categories are available (incidente first, null last)
    final sorted = List<String>.of(widget.evidenceIds);
    if (widget.categories.isNotEmpty) {
      sorted.sort(
        (a, b) => EvidenceCategoryChip.sortPriority(
          widget.categories[a],
        ).compareTo(EvidenceCategoryChip.sortPriority(widget.categories[b])),
      );
    }
    final items = sorted.take(EvidenceDossierModal._kMaxItems).toList();

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
                    _headerLabel,
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
          // ── Compliance checklist (optional) ──
          if (widget.compliance != null)
            EvidenceComplianceChecklist(compliance: widget.compliance!),
          // ── Grid ──
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: widget.categories.isNotEmpty ? 0.78 : 1.0,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final id = items[index];
                // INV-26: ALL files MUST go through secure-evidence-proxy
                final url =
                    '${EnvironmentConfig.supabaseUrl}/functions/v1/secure-evidence-proxy?evidence_id=$id'; // pr_scanner: ignore

                // ── Audio evidence → ForensicAudioPlayer ──
                if (_isAudio(id)) {
                  final player = ForensicAudioPlayer(
                    audioUrl: url,
                    forensicHash:
                        id, // evidence ID as fallback hash for waveform
                    httpHeaders: {'Authorization': 'Bearer $accessToken'},
                  );
                  if (widget.categories.isNotEmpty) {
                    final cat = widget.categories[id];
                    return Column(
                      children: [
                        Expanded(child: player),
                        const SizedBox(height: 3),
                        EvidenceCategoryChip(category: cat),
                      ],
                    );
                  }
                  return player;
                }

                // ── Photo/document evidence → CachedNetworkImage ──
                final image = ClipRRect(
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

                // Show category caption when categories map is provided
                if (widget.categories.isNotEmpty) {
                  final cat = widget.categories[id];
                  return Column(
                    children: [
                      Expanded(child: image),
                      const SizedBox(height: 3),
                      EvidenceCategoryChip(category: cat),
                    ],
                  );
                }
                return image;
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
