import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';

import '../screens/operational_zones_screen.dart';

// ── Filter helper (top-level for testability) ─────────────────

/// Filters [zones] visible to [currentContractor]:
/// - [ZoneScope.global] zones (no contractor label) are always included
/// - [ZoneScope.exclusive] zones are only included when their label matches [currentContractor]
///
/// Then applies a case-insensitive substring match on [query] (when non-empty).
/// Preserves the input order — sorting is the caller's responsibility.
List<OperationalZone> filterZones(
  List<OperationalZone> zones,
  String query,
  String currentContractor,
) {
  var filtered = zones
      .where(
        (z) =>
            z.scope == ZoneScope.global ||
            z.contractorLabel == currentContractor,
      )
      .toList();

  if (query.isNotEmpty) {
    final lower = query.toLowerCase();
    filtered = filtered
        .where((z) => z.name.toLowerCase().contains(lower))
        .toList();
  }
  return filtered;
}

// ── Widget ────────────────────────────────────────────────────

/// A type-ahead (autocomplete) field for selecting or Just-in-Time creating an
/// [OperationalZone].
///
/// Displays existing zones as autocomplete suggestions, scoped by
/// [contractorName] — zones belonging to a different contractor are hidden.
/// When the operator types a name that does not match, a "+ Criar zona"
/// option is shown below the field. Tapping it opens the native
/// [showZoneFormDialog] (map + Nominatim) instead of an inline mini-form.
///
/// After a zone is created via the modal, [onInvalidateZones] is called so
/// the parent can reload the provider, and [onChanged] is called with the
/// freshly created zone so it is immediately selected.
///
/// Use [key: ValueKey(selectedZone?.id)] in the parent so that Flutter
/// reconstructs this widget when the selection is swapped externally
/// (e.g., origin ↔ destination return-shift).
class ZoneTypeAheadField extends StatefulWidget {
  final String label;
  final IconData prefixIcon;

  /// Pre-sorted list from the parent. Contractor zones should appear first.
  final List<OperationalZone> zones;

  /// The currently selected zone (can be null when nothing is selected yet).
  final OperationalZone? selectedZone;

  /// Contract's contractor name — used to filter visible zones and to
  /// auto-apply as [contractorLabel] on newly-created zones.
  final String contractorName;

  /// Invalidates the zones cache after the modal creates/edits a zone.
  final Future<void> Function() onInvalidateZones;

  /// Called when the user selects an existing zone or after zone creation.
  final ValueChanged<OperationalZone?> onChanged;

  /// Called after the operator configures a geofence via [showZoneFormDialog]
  /// with the updated zone object.
  final ValueChanged<OperationalZone>? onGeofenceConfigured;

  const ZoneTypeAheadField({
    super.key,
    required this.label,
    required this.prefixIcon,
    required this.zones,
    required this.selectedZone,
    required this.contractorName,
    required this.onInvalidateZones,
    required this.onChanged,
    this.onGeofenceConfigured,
  });

  @override
  State<ZoneTypeAheadField> createState() => _ZoneTypeAheadFieldState();
}

class _ZoneTypeAheadFieldState extends State<ZoneTypeAheadField> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _fieldFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textController.text = widget.selectedZone?.name ?? '';
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textController.dispose();
    _fieldFocusNode.dispose();
    super.dispose();
  }

  // ── Modal creation ────────────────────────────────────────────

  Future<void> _triggerCreationDialog() async {
    final zone = await showZoneFormDialog(context);
    if (!mounted || zone == null) return;
    // Select the zone immediately, before the async provider refresh.
    // This prevents the parent from rebuilding without a selection while
    // the provider transitions through its loading state.
    _textController.text = zone.name;
    widget.onChanged(zone);
    await widget.onInvalidateZones();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAutocomplete(),
        _buildCreateButton(),
        _buildGeofenceWarning(),
      ],
    );
  }

  /// Shows "+ Criar zona 'X'" below the field when no exact name match exists.
  Widget _buildCreateButton() {
    final query = _textController.text.trim();
    final hasExactMatch =
        query.isNotEmpty &&
        widget.zones.any((z) => z.name.toLowerCase() == query.toLowerCase());
    if (hasExactMatch) return const SizedBox.shrink();

    final label = query.isEmpty ? '+ Criar nova zona' : '+ Criar zona "$query"';

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.add_location_alt, size: 14),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: VeraProbColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: _triggerCreationDialog,
      ),
    );
  }

  Widget _buildAutocomplete() {
    return Autocomplete<OperationalZone>(
      initialValue: TextEditingValue(text: widget.selectedZone?.name ?? ''),
      optionsBuilder: (textEditingValue) {
        return filterZones(
          widget.zones,
          textEditingValue.text,
          widget.contractorName,
        );
      },
      displayStringForOption: (zone) => zone.name,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        final selectedZone = widget.selectedZone;
        final hasGeofence = selectedZone?.geofence != null;

        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(widget.prefixIcon),
            suffixIcon: selectedZone != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasGeofence ? Icons.location_on : Icons.location_off,
                        size: 18,
                        color: hasGeofence
                            ? VeraProbColors.onTime
                            : VeraProbColors.warning,
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          widget.onChanged(null);
                          controller.clear();
                          focusNode.unfocus();
                        },
                      ),
                    ],
                  )
                : null,
          ),
          onChanged: (v) => _textController.text = v,
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final optionList = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 480),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: optionList.length,
                itemBuilder: (context, index) {
                  final zone = optionList[index];
                  final hasGeo = zone.geofence != null;
                  final isContractor =
                      widget.contractorName.isNotEmpty &&
                      zone.contractorLabel == widget.contractorName;

                  return ListTile(
                    leading: Icon(
                      hasGeo ? Icons.location_on : Icons.location_off,
                      size: 18,
                      color: hasGeo
                          ? VeraProbColors.onTime
                          : VeraProbColors.warning,
                    ),
                    title: Text(zone.name),
                    trailing: isContractor
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: VeraProbSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: VeraProbColors.primary.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Seu contratante',
                              style: VeraProbTypography.fieldLabel.copyWith(
                                color: VeraProbColors.primary,
                              ),
                            ),
                          )
                        : null,
                    onTap: () => onSelected(zone),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (zone) {
        _textController.text = zone.name;
        widget.onChanged(zone);
      },
    );
  }

  Widget _buildGeofenceWarning() {
    final zone = widget.selectedZone;
    if (zone == null || zone.geofence != null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        icon: const Icon(Icons.edit_location_alt, size: 14),
        label: const Text('Configurar Geofence →'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () async {
          final saved = await showZoneFormDialog(context, existingZone: zone);
          if (!mounted || saved == null) return;
          widget.onGeofenceConfigured?.call(saved);
          await widget.onInvalidateZones();
        },
      ),
    );
  }
}
