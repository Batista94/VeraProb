import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';

/// Shows a human-readable address for [lat]/[lng] via reverse geocoding.
///
/// Always renders a location: coordinates are the fallback while loading or
/// on error, so the operator never sees a blank where a place should be.
class ReverseGeocodedAddress extends ConsumerWidget {
  final double lat;
  final double lng;

  const ReverseGeocodedAddress({
    super.key,
    required this.lat,
    required this.lng,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Round to 4dp so nearby points share one provider cache entry.
    final rLat = double.parse(lat.toStringAsFixed(4));
    final rLng = double.parse(lng.toStringAsFixed(4));
    final address = ref.watch(reverseGeocodeProvider((rLat, rLng)));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.place_outlined,
          size: 14,
          color: VeraProbColors.textSecondary,
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
      ],
    );
  }

  TextStyle get _style => VeraProbTypography.bodySmall;

  String get _coordinates =>
      '${lat.toStringAsFixed(4)}°, ${lng.toStringAsFixed(4)}°';
}
