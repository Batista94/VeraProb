import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';

/// Shows a human-readable address for [lat]/[lng] via reverse geocoding.
///
/// Always renders a location: coordinates are the fallback while loading or
/// on error, so the operator never sees a blank where a place should be.
///
/// When [onTap] is provided, the widget renders with click affordance:
/// pointer cursor, subtle hover highlight, and a trailing open-in-new icon.
class ReverseGeocodedAddress extends ConsumerStatefulWidget {
  final double lat;
  final double lng;
  final VoidCallback? onTap;

  const ReverseGeocodedAddress({
    super.key,
    required this.lat,
    required this.lng,
    this.onTap,
  });

  @override
  ConsumerState<ReverseGeocodedAddress> createState() =>
      _ReverseGeocodedAddressState();
}

class _ReverseGeocodedAddressState
    extends ConsumerState<ReverseGeocodedAddress> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // Round to 4dp so nearby points share one provider cache entry.
    final rLat = double.parse(widget.lat.toStringAsFixed(4));
    final rLng = double.parse(widget.lng.toStringAsFixed(4));
    final address = ref.watch(reverseGeocodeProvider((rLat, rLng)));
    final isInteractive = widget.onTap != null;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: _isHovered && isInteractive
            ? VeraProbColors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.place_outlined,
            size: 14,
            color: _isHovered && isInteractive
                ? VeraProbColors.primary
                : VeraProbColors.textSecondary,
          ),
          const SizedBox(width: VeraProbSpacing.xs),
          Expanded(
            child: address.when(
              loading: () => const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              error: (_, _) => Text(_coordinates, style: _style),
              data: (value) => Text(value ?? _coordinates, style: _style),
            ),
          ),
          if (isInteractive) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.center_focus_strong,
              size: 12,
              color: _isHovered
                  ? VeraProbColors.primary
                  : VeraProbColors.textDisabled,
            ),
          ],
        ],
      ),
    );

    if (!isInteractive) return content;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: 'Recentrar mapa no ponto de infração',
        child: GestureDetector(onTap: widget.onTap, child: content),
      ),
    );
  }

  TextStyle get _style => VeraProbTypography.bodySmall;

  String get _coordinates =>
      '${widget.lat.toStringAsFixed(4)}°, ${widget.lng.toStringAsFixed(4)}°';
}
