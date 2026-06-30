import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/session_recovery.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/zone_ui_utils.dart';

/// Opens the zone create/edit dialog.
/// Returns the saved [OperationalZoneView] on success, null on cancel.
Future<OperationalZoneView?> showZoneFormDialog(
  BuildContext context, {
  OperationalZoneView? existingZone,
}) {
  return showDialog<OperationalZoneView>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ZoneFormDialog(existingZone: existingZone),
  );
}

class _ZoneFormDialog extends ConsumerStatefulWidget {
  final OperationalZoneView? existingZone;
  const _ZoneFormDialog({this.existingZone});

  @override
  ConsumerState<_ZoneFormDialog> createState() => _ZoneFormDialogState();
}

class _ZoneFormDialogState extends ConsumerState<_ZoneFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _radiusController = TextEditingController(text: '200');
  final _mapController = MapController();

  ZoneType _selectedType = ZoneType.garagem;
  double? _lat;
  double? _lng;

  bool _isSubmitting = false;
  bool _isCancelled = false;
  String? _errorMessage;

  // Nominatim address search state
  List<_PlaceSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _isSearching = false;

  // G3 — FocusNodes
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();
  final FocusNode _radiusFocus = FocusNode();

  static const _defaultCenter = LatLng(-23.5505, -46.6333);
  static const _defaultZoom = 11.0;
  static const _pinZoom = 15.0;

  @override
  void initState() {
    super.initState();
    final zone = widget.existingZone;
    if (zone != null) {
      _nameController.text = zone.name;
      _addressController.text = zone.address ?? '';
      _selectedType = zone.type;
      if (zone.geofence != null) {
        _lat = zone.geofence!.latitude;
        _lng = zone.geofence!.longitude;
        _radiusController.text = zone.geofence!.radiusMeters.toString();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _radiusController.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    _radiusFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Nominatim geocoding ───────────────────────────────────

  void _onAddressChanged(String query) {
    _debounce?.cancel();
    if (query.length < 4) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      try {
        final results = await ref.read(geocodingSearchProvider(query).future);
        if (mounted) {
          setState(() {
            _suggestions = results;
            _isSearching = false;
          });
        }
      } on ProviderException catch (e) {
        // Riverpod v3: unwrap ProviderException to get original error
        debugPrint('Geocoding search failed: ${e.exception}');
        if (mounted) setState(() => _isSearching = false);
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  // Removed _searchNominatim direct call (moved to GeocodingRepository)

  void _selectSuggestion(_PlaceSuggestion s) {
    setState(() {
      _addressController.text = s.displayName;
      _lat = s.lat;
      _lng = s.lng;
      _suggestions = [];
      _errorMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(LatLng(s.lat, s.lng), _pinZoom);
      } catch (_) {}
    });
  }

  void _clearSuggestions() => setState(() => _suggestions = []);

  // ── Map pin drop ─────────────────────────────────────────

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      _lat = point.latitude;
      _lng = point.longitude;
      _errorMessage = null;
    });
  }

  // ── Submit ───────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (widget.existingZone == null && (_lat == null || _lng == null)) {
      setState(
        () => _errorMessage =
            'Toque no mapa ou busque um endereço para definir a localização da zona antes de salvar.',
      );
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final navigator = Navigator.of(context);

    try {
      // Resilient session recovery: attempt token refresh before giving up
      final orgId = await SessionRecovery.ensureOrgIdWidget(ref);
      if (orgId == null) {
        throw const DomainException('Sessão expirada. Faça login novamente.');
      }

      GeofenceView? geofence;
      if (_lat != null && _lng != null) {
        final radius = int.tryParse(_radiusController.text.trim()) ?? 200;
        geofence = GeofenceView(
          latitude: _lat!,
          longitude: _lng!,
          radiusMeters: radius,
        );
      }

      final OperationalZoneView zone;
      if (widget.existingZone != null) {
        // EDIT: use existing ID
        zone = OperationalZoneView(
          id: widget.existingZone!.id,
          organizationId: orgId,
          name: _nameController.text.trim(),
          type: _selectedType,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          contractorId: widget.existingZone!.contractorId,
          geofence: geofence,
        );
      } else {
        // CREATE: new UUID
        zone = OperationalZoneView(
          id: const Uuid().v4(),
          organizationId: orgId,
          name: _nameController.text.trim(),
          type: _selectedType,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          geofence: geofence,
        );
      }

      await saveZone(zone, ref);
      if (!mounted || _isCancelled) return;
      navigator.pop(zone);
    } on DomainException catch (e) {
      if (!mounted || _isCancelled) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted || _isCancelled) return;
      setState(
        () => _errorMessage = 'Ocorreu um erro inesperado ao salvar a zona.',
      );
    } finally {
      if (mounted && !_isCancelled) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingZone != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.92).clamp(
            400.0,
            960.0,
          ),
          maxHeight: (MediaQuery.sizeOf(context).height * 0.88).clamp(
            480.0,
            720.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isEdit),
              const Divider(height: 24, color: VeraProbColors.border),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(right: 16),
                          child: _buildFormFields(),
                        ),
                      ),
                    ),
                    Expanded(flex: 3, child: _buildMap()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildFooter(isEdit),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isEdit) {
    return Row(
      children: [
        Icon(
          isEdit ? Icons.edit_location_alt : Icons.add_location_alt,
          color: VeraProbColors.primary,
        ),
        const SizedBox(width: 12),
        Text(
          isEdit ? 'Editar Zona Operacional' : 'Nova Zona Operacional',
          style: VeraProbTypography.sectionTitle,
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ],
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<ZoneType>(
      initialValue: _selectedType,
      decoration: const InputDecoration(labelText: 'Tipo *'),
      items: ZoneType.values
          .map(
            (t) => DropdownMenuItem(
              value: t,
              child: Row(
                children: [
                  Icon(t.icon, size: 18),
                  const SizedBox(width: 8),
                  Text(t.label),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _selectedType = v!),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      focusNode: _nameFocus,
      decoration: const InputDecoration(
        labelText: 'Nome da Zona *',
        hintText: 'Ex: Garagem Central, Portaria Sul',
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
      autofocus: widget.existingZone == null,
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
    );
  }

  Widget _buildAddressSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _addressController,
          focusNode: _addressFocus,
          decoration: InputDecoration(
            labelText: 'Endereço',
            hintText: 'Digite para buscar e geolocalizar...',
            prefixIcon: const Icon(Icons.search, size: 18),
            helperText: 'OpenStreetMap · ou clique no mapa para posicionar',
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_suggestions.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: _clearSuggestions,
                        )
                      : null),
          ),
          onChanged: _onAddressChanged,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: VeraProbColors.border),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              itemBuilder: (context, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: VeraProbColors.primary,
                  ),
                  title: Text(
                    s.displayName,
                    style: VeraProbTypography.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _selectSuggestion(s),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMapLocationSection() {
    return ExpansionTile(
      leading: Icon(
        Icons.radar,
        color: _lat != null ? VeraProbColors.success : VeraProbColors.warning,
      ),
      title: const Text('Localização no Mapa *'),
      subtitle: Text(
        _lat != null ? 'Localização definida' : 'Necessário para monitoramento',
        style: TextStyle(
          color: _lat != null ? VeraProbColors.success : VeraProbColors.warning,
          fontSize: 12,
        ),
      ),
      initiallyExpanded: true,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_lat != null && _lng != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: VeraProbColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: VeraProbColors.success.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.my_location,
                        size: 14,
                        color: VeraProbColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: VeraProbColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _lat = null;
                          _lng = null;
                        }),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Limpar',
                          style: TextStyle(
                            fontSize: 11,
                            color: VeraProbColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: VeraProbColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: VeraProbColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 16,
                        color: VeraProbColors.warning,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Busque um endereço acima ou toque no mapa para '
                          'marcar a localização da zona.',
                          style: TextStyle(
                            fontSize: 11,
                            color: VeraProbColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              TextFormField(
                controller: _radiusController,
                focusNode: _radiusFocus,
                decoration: const InputDecoration(
                  labelText: 'Distância de Detecção',
                  suffixText: 'm',
                  helperText:
                      'Raio em metros para detectar chegada e saída da zona.',
                  helperMaxLines: 2,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (_lat == null) return null;
                  if (v == null || v.isEmpty) {
                    return 'Obrigatório quando localização está definida';
                  }
                  final n = int.tryParse(v);
                  if (n == null || n <= 0 || n > 50000) {
                    return '1 a 50.000 m';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTypeDropdown(),
        const SizedBox(height: 16),
        _buildNameField(),
        const SizedBox(height: 16),
        _buildAddressSearchField(),
        const SizedBox(height: 16),
        _buildMapLocationSection(),
      ],
    );
  }

  Widget _buildMap() {
    final hasPin = _lat != null && _lng != null;
    final center = hasPin ? LatLng(_lat!, _lng!) : _defaultCenter;
    final zoom = hasPin ? _pinZoom : _defaultZoom;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.veraprob',
              ),
              if (hasPin)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_lat!, _lng!),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: VeraProbColors.error,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Instruction overlay
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, color: Colors.white, size: 13),
                  SizedBox(width: 4),
                  Text(
                    'Clique no mapa para posicionar o pin',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          // OSM attribution
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              color: Colors.white.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 9, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isEdit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: VeraProbColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: VeraProbColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: VeraProbColors.error,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: VeraProbColors.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                _isCancelled = true;
                Navigator.of(context).pop(null);
              },
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isEdit ? Icons.save : Icons.add_location_alt,
                      size: 18,
                    ),
              label: Text(isEdit ? 'Salvar Zona' : 'Criar Zona'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Place suggestion (Nominatim result) ──────────────────────

typedef _PlaceSuggestion = PlaceSuggestion;
