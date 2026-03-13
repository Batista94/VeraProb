import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/domain/sla_audit/operational_zone.dart';
import 'package:busflow/state/providers/operational_zone_providers.dart';

import '../screens/operational_zones_screen.dart';

// ── Filter helper (top-level for testability) ─────────────────

/// Filters [zones] by [query] (case-insensitive substring on name).
/// Returns all zones unchanged when [query] is empty.
/// Preserves the input order — sorting is the caller's responsibility.
List<OperationalZone> filterZones(
  List<OperationalZone> zones,
  String query,
) {
  if (query.isEmpty) return zones;
  final lower = query.toLowerCase();
  return zones.where((z) => z.name.toLowerCase().contains(lower)).toList();
}

// ── Widget ────────────────────────────────────────────────────

/// A type-ahead (autocomplete) field for selecting or inline-creating an
/// [OperationalZone].
///
/// Displays existing zones as autocomplete suggestions. When the operator
/// types a name that does not match, a "+ Criar zona" option is shown at
/// the bottom of the overlay. Tapping it expands an inline mini-form that
/// saves the zone eagerly via [saveZone] before returning the new zone
/// through [onChanged].
///
/// The [contractorLabel] is automatically set to [contractorName] during
/// inline creation — the operator does not see or edit it.
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

  /// Contract's contractor name — auto-applied as [contractorLabel] on
  /// zones created inline.
  final String contractorName;

  /// Organization ID from the authenticated session JWT.
  final String organizationId;

  /// Persists a newly-created zone. Called with `saveZone(zone, ref)` from
  /// the parent's [ConsumerState] so the ref is always valid.
  final Future<void> Function(OperationalZone) onSaveZone;

  /// Invalidates the zones cache after a geofence edit via [showZoneFormDialog].
  final Future<void> Function() onInvalidateZones;

  /// Called when the user selects an existing zone or finishes creating a
  /// new one.
  final ValueChanged<OperationalZone?> onChanged;

  /// Called after the operator configures a geofence via the existing
  /// [showZoneFormDialog] so the parent can trigger a UI refresh.
  final VoidCallback? onGeofenceConfigured;

  const ZoneTypeAheadField({
    super.key,
    required this.label,
    required this.prefixIcon,
    required this.zones,
    required this.selectedZone,
    required this.contractorName,
    required this.organizationId,
    required this.onSaveZone,
    required this.onInvalidateZones,
    required this.onChanged,
    this.onGeofenceConfigured,
  });

  @override
  State<ZoneTypeAheadField> createState() => _ZoneTypeAheadFieldState();
}

class _ZoneTypeAheadFieldState extends State<ZoneTypeAheadField> {
  // ── Autocomplete ─────────────────────────────────────────────
  final TextEditingController _textController = TextEditingController();
  final FocusNode _fieldFocusNode = FocusNode();

  // ── Mini-form visibility ──────────────────────────────────────
  bool _showCreationForm = false;
  bool _isSaving = false;
  String? _saveError;

  // ── Mini-form fields ──────────────────────────────────────────
  final TextEditingController _newNameCtrl = TextEditingController();
  final TextEditingController _newAddressCtrl = TextEditingController();
  final TextEditingController _newLatCtrl = TextEditingController();
  final TextEditingController _newLngCtrl = TextEditingController();
  final TextEditingController _newRadiusCtrl =
      TextEditingController(text: '200');
  ZoneType _newZoneType = ZoneType.garagem;

  @override
  void initState() {
    super.initState();
    _textController.text = widget.selectedZone?.name ?? '';
    // Rebuild so the inline "+ Criar" button shows/hides as the user types.
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textController.dispose();
    _fieldFocusNode.dispose();
    _newNameCtrl.dispose();
    _newAddressCtrl.dispose();
    _newLatCtrl.dispose();
    _newLngCtrl.dispose();
    _newRadiusCtrl.dispose();
    super.dispose();
  }

  // ── Creation form control ─────────────────────────────────────

  void _triggerCreationForm(String prefillName) {
    setState(() {
      _showCreationForm = true;
      _saveError = null;
    });
    _newNameCtrl.text = prefillName.trim();
  }

  void _cancelCreation() {
    setState(() {
      _showCreationForm = false;
      _saveError = null;
      _newZoneType = ZoneType.garagem;
    });
    _newNameCtrl.clear();
    _newAddressCtrl.clear();
    _newLatCtrl.clear();
    _newLngCtrl.clear();
    _newRadiusCtrl.text = '200';
  }

  Future<void> _submitCreation() async {
    if (widget.organizationId.isEmpty) {
      setState(() => _saveError = 'Sessão expirada. Faça login novamente.');
      return;
    }

    // Validate geofence: all-or-nothing
    final latStr = _newLatCtrl.text.trim();
    final lngStr = _newLngCtrl.text.trim();
    final radStr = _newRadiusCtrl.text.trim();
    final geoFilled = [latStr, lngStr, radStr].where((s) => s.isNotEmpty);
    if (geoFilled.isNotEmpty && geoFilled.length < 3) {
      setState(() => _saveError =
          'Preencha Latitude, Longitude e Raio juntos ou deixe todos em branco.');
      return;
    }

    GeofenceConfiguration? geofence;
    if (geoFilled.length == 3) {
      final lat = double.tryParse(latStr.replaceAll(',', '.'));
      final lng = double.tryParse(lngStr.replaceAll(',', '.'));
      final rad = int.tryParse(radStr);
      if (lat == null || lng == null || rad == null || rad <= 0) {
        setState(
            () => _saveError = 'Valores de geofence inválidos. Verifique os campos.');
        return;
      }
      geofence = GeofenceConfiguration(
        latitude: lat,
        longitude: lng,
        radiusMeters: rad,
      );
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final newZone = OperationalZone.create(
        organizationId: widget.organizationId,
        name: _newNameCtrl.text.trim(),
        type: _newZoneType,
        address: _newAddressCtrl.text.trim().isEmpty
            ? null
            : _newAddressCtrl.text.trim(),
        contractorLabel: widget.contractorName.isEmpty
            ? null
            : widget.contractorName,
        geofence: geofence,
      );

      await widget.onSaveZone(newZone);

      if (!mounted) return;
      _textController.text = newZone.name;
      _cancelCreation();
      widget.onChanged(newZone);
    } on DomainException catch (e) {
      if (!mounted) return;
      // 23505 duplicate name — make message actionable
      final msg = e.message.contains('Já existe')
          ? 'Já existe uma zona com este nome. Selecione-a na lista acima.'
          : e.message;
      setState(() => _saveError = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        _buildCreationFormAnimated(),
      ],
    );
  }

  /// Shows an inline "+ Criar zona 'X'" button when the typed text does not
  /// match any existing zone exactly and the mini-form is not already open.
  Widget _buildCreateButton() {
    if (_showCreationForm) return const SizedBox.shrink();
    final query = _textController.text.trim();
    // Hide when mini-form is open or when text exactly matches an existing zone
    // (user has already selected; allow clicking overlay item instead).
    final hasExactMatch = query.isNotEmpty &&
        widget.zones.any((z) => z.name.toLowerCase() == query.toLowerCase());
    if (hasExactMatch) return const SizedBox.shrink();

    final label = query.isEmpty ? '+ Criar nova zona' : '+ Criar zona "$query"';

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.add_location_alt, size: 14),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: BusFlowColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => _triggerCreationForm(query),
      ),
    );
  }

  Widget _buildAutocomplete() {
    return Autocomplete<OperationalZone>(
      optionsBuilder: (textEditingValue) {
        // Return all zones (sorted by parent) for empty queries so the field
        // behaves like a searchable dropdown.
        return filterZones(widget.zones, textEditingValue.text);
      },
      displayStringForOption: (zone) => zone.name,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        // Sync the parent-owned display text on first render.
        // (The autocomplete creates its own controller internally; we keep
        // _textController in sync to display the selected zone name after
        // creation / external swap via ValueKey.)
        if (controller.text.isEmpty && _textController.text.isNotEmpty) {
          controller.text = _textController.text;
        }
        controller.addListener(() => _textController.text = controller.text);

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
                ? Icon(
                    hasGeofence ? Icons.location_on : Icons.location_off,
                    size: 18,
                    color: hasGeofence
                        ? BusFlowColors.onTime
                        : BusFlowColors.warning,
                  )
                : null,
          ),
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
                  final isContractor = widget.contractorName.isNotEmpty &&
                      zone.contractorLabel == widget.contractorName;

                  return ListTile(
                    leading: Icon(
                      hasGeo ? Icons.location_on : Icons.location_off,
                      size: 18,
                      color:
                          hasGeo ? BusFlowColors.onTime : BusFlowColors.warning,
                    ),
                    title: Text(zone.name),
                    trailing: isContractor
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: BusFlowSpacing.xs, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  BusFlowColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Seu contratante',
                              style: BusFlowTypography.fieldLabel.copyWith(
                                color: BusFlowColors.primary,
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
    if (zone == null || zone.geofence != null || _showCreationForm) {
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
          final saved = await showZoneFormDialog(
            context,
            existingZone: zone,
          );
          if (saved == true) {
            await widget.onInvalidateZones();
            widget.onGeofenceConfigured?.call();
          }
        },
      ),
    );
  }

  Widget _buildCreationFormAnimated() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: _showCreationForm ? _buildCreationForm() : const SizedBox.shrink(),
    );
  }

  Widget _buildCreationForm() {
    return Container(
      margin: const EdgeInsets.only(top: BusFlowSpacing.sm),
      padding: const EdgeInsets.all(BusFlowSpacing.md),
      decoration: BoxDecoration(
        color: BusFlowColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BusFlowColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              const Icon(
                Icons.add_location_alt,
                color: BusFlowColors.primary,
                size: 16,
              ),
              const SizedBox(width: BusFlowSpacing.xs),
              Text(
                'Nova Zona',
                style: BusFlowTypography.fieldLabel.copyWith(
                  color: BusFlowColors.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: _cancelCreation,
              ),
            ],
          ),
          const SizedBox(height: BusFlowSpacing.md),

          // Nome
          TextFormField(
            key: const Key('zone_mini_form_name'),
            controller: _newNameCtrl,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Nome *',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: BusFlowSpacing.sm),

          // Tipo
          // ignore: deprecated_member_use
          DropdownButtonFormField<ZoneType>(
            value: _newZoneType,
            decoration: const InputDecoration(
              labelText: 'Tipo',
              border: OutlineInputBorder(),
            ),
            items: ZoneType.values.map((t) {
              return DropdownMenuItem(
                value: t,
                child: Row(
                  children: [
                    Icon(t.icon, size: 16),
                    const SizedBox(width: BusFlowSpacing.xs),
                    Text(t.label),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _newZoneType = v);
            },
          ),
          const SizedBox(height: BusFlowSpacing.sm),

          // Endereço (opcional)
          TextFormField(
            controller: _newAddressCtrl,
            decoration: const InputDecoration(
              labelText: 'Endereço (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: BusFlowSpacing.sm),

          // Geofence (ExpansionTile)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Geofence (recomendado)',
                style: BusFlowTypography.fieldLabel,
              ),
              childrenPadding: const EdgeInsets.only(top: BusFlowSpacing.sm),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('zone_mini_form_lat'),
                        controller: _newLatCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: BusFlowSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _newLngCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: BusFlowSpacing.sm),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _newRadiusCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Raio (m)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BusFlowSpacing.xs),
                Text(
                  'Sem geofence? Salve a zona e configure depois via "Configurar Geofence →"',
                  style: BusFlowTypography.fieldLabel.copyWith(
                    color: BusFlowColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Error message
          if (_saveError != null) ...[
            const SizedBox(height: BusFlowSpacing.sm),
            Container(
              padding: const EdgeInsets.all(BusFlowSpacing.sm),
              decoration: BoxDecoration(
                color: BusFlowColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: BusFlowColors.error.withValues(alpha: 0.4)),
              ),
              child: Text(
                _saveError!,
                style: const TextStyle(
                  color: BusFlowColors.error,
                  fontSize: 13,
                ),
              ),
            ),
          ],

          const SizedBox(height: BusFlowSpacing.md),

          // Footer buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelCreation,
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: BusFlowSpacing.sm),
              FilledButton(
                key: const Key('zone_mini_form_submit'),
                onPressed: _isSaving ? null : _submitCreation,
                child: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Criar Zona'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
