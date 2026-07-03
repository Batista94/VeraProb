import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

import 'package:veraprob/features/admin/presentation/screens/widgets/_zone_form_dialog.dart';

// ── Filter helper (top-level for testability) ─────────────────

/// Filters [zones] by a case-insensitive substring match on [query].
/// When [query] is empty, all zones are returned.
/// Preserves the input order — sorting is the caller's responsibility.
List<OperationalZoneView> filterZones(
  List<OperationalZoneView> zones,
  String query,
) {
  if (query.isEmpty) return zones;
  final lower = query.toLowerCase();
  return zones.where((z) => z.name.toLowerCase().contains(lower)).toList();
}

// ── Widget ────────────────────────────────────────────────────

/// A type-ahead (autocomplete) field for selecting or Just-in-Time creating an
/// [OperationalZoneView].
///
/// When the operator types a name that does not match any zone, a "+ Criar zona"
/// option is shown below the field. Tapping it opens [showZoneFormDialog]
/// (map + Nominatim) instead of an inline mini-form.
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

  /// Pre-sorted list from the parent.
  final List<OperationalZoneView> zones;

  /// The currently selected zone (can be null when nothing is selected yet).
  final OperationalZoneView? selectedZone;

  /// Invalidates the zones cache after the modal creates/edits a zone.
  final Future<void> Function() onInvalidateZones;

  /// Called when the user selects an existing zone or after zone creation.
  final ValueChanged<OperationalZoneView?> onChanged;

  /// Called after the operator configures a geofence via [showZoneFormDialog]
  /// with the updated zone object.
  final ValueChanged<OperationalZoneView>? onGeofenceConfigured;

  const ZoneTypeAheadField({
    super.key,
    required this.label,
    required this.prefixIcon,
    required this.zones,
    required this.selectedZone,
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
    return Autocomplete<OperationalZoneView>(
      initialValue: TextEditingValue(text: widget.selectedZone?.name ?? ''),
      optionsBuilder: (textEditingValue) {
        // When the field text equals the selected zone name, show all available
        // zones instead of filtering — allows the user to change the selection
        // without first clearing the field manually.
        final selectedName = widget.selectedZone?.name ?? '';
        final query = textEditingValue.text == selectedName
            ? ''
            : textEditingValue.text;
        return filterZones(widget.zones, query);
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
            borderRadius: VeraProbRadii.mdAll,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 280,
                maxWidth: (MediaQuery.sizeOf(context).width * 0.9).clamp(
                  240.0,
                  480.0,
                ),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: optionList.length,
                itemBuilder: (context, index) {
                  final zone = optionList[index];
                  final hasGeo = zone.geofence != null;

                  return ListTile(
                    leading: Icon(
                      hasGeo ? Icons.location_on : Icons.location_off,
                      size: 18,
                      color: hasGeo
                          ? VeraProbColors.onTime
                          : VeraProbColors.warning,
                    ),
                    title: Text(
                      zone.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
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

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VeraProbColors.warning.withValues(alpha: 0.08),
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(
          color: VeraProbColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_off,
            size: 16,
            color: VeraProbColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${zone.name} ainda não tem localização no mapa. '
              'Defina agora para ativar o monitoramento.',
              style: const TextStyle(
                fontSize: 12,
                color: VeraProbColors.warning,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              final saved = await showZoneFormDialog(
                context,
                existingZone: zone,
              );
              if (!mounted || saved == null) return;
              widget.onGeofenceConfigured?.call(saved);
              await widget.onInvalidateZones();
            },
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.warning,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Definir Localização',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
