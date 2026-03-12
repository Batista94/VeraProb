import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/domain/sla_audit/operational_zone.dart';
import 'package:busflow/state/providers/auth_providers.dart';
import 'package:busflow/state/providers/operational_zone_providers.dart';

// ── Public API ───────────────────────────────────────────────

/// Opens the zone create/edit dialog.
/// Returns true when the zone was saved successfully, false/null otherwise.
Future<bool?> showZoneFormDialog(
  BuildContext context, {
  OperationalZone? existingZone,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ZoneFormDialog(existingZone: existingZone),
  );
}

// ── ZoneType extensions ──────────────────────────────────────

extension on ZoneType {
  String get label => switch (this) {
        ZoneType.garagem => 'Garagem',
        ZoneType.cliente => 'Cliente',
        ZoneType.apoio => 'Apoio',
      };

  IconData get icon => switch (this) {
        ZoneType.garagem => Icons.garage_outlined,
        ZoneType.cliente => Icons.business_outlined,
        ZoneType.apoio => Icons.support_agent_outlined,
      };
}

// ── Screen ───────────────────────────────────────────────────

/// Tela de gestão de Zonas Operacionais (CRUD completo).
class OperationalZonesScreen extends ConsumerWidget {
  const OperationalZonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(operationalZonesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  size: 28, color: BusFlowColors.primary),
              const SizedBox(width: 12),
              Text('Zonas Operacionais', style: BusFlowTypography.sectionTitle),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nova Zona Operacional'),
                onPressed: () async {
                  final saved = await showZoneFormDialog(context);
                  if (saved == true) ref.invalidate(operationalZonesProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Garagens, clientes e pontos de apoio usados como origem/destino '
            'nas viagens programadas. Geofence (coordenadas + raio) é obrigatório '
            'para auditoria automática pelo motor de avaliação.',
            style: BusFlowTypography.bodyMedium
                .copyWith(color: BusFlowColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: zonesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar zonas: $e',
                  style: BusFlowTypography.bodyMedium
                      .copyWith(color: BusFlowColors.error),
                ),
              ),
              data: (zones) => zones.isEmpty
                  ? _EmptyState(onCreateTap: () async {
                      final saved = await showZoneFormDialog(context);
                      if (saved == true) {
                        ref.invalidate(operationalZonesProvider);
                      }
                    })
                  : _ZoneList(zones: zones),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Zone list ────────────────────────────────────────────────

class _ZoneList extends ConsumerWidget {
  final List<OperationalZone> zones;
  const _ZoneList({required this.zones});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      itemCount: zones.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: BusFlowColors.border),
      itemBuilder: (context, i) {
        final z = zones[i];
        final hasGeofence = z.geofence != null;
        final geoLabel = hasGeofence
            ? '${z.geofence!.radiusMeters} m  ·  '
                '${z.geofence!.latitude.toStringAsFixed(5)}, '
                '${z.geofence!.longitude.toStringAsFixed(5)}'
            : 'Sem geofence — configure para auditoria automática';

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: BusFlowColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(z.type.icon, color: BusFlowColors.primary, size: 20),
          ),
          title: Row(
            children: [
              Text(z.name, style: BusFlowTypography.kpiLabel),
              const SizedBox(width: 8),
              _TypeChip(label: z.type.label),
              if (!hasGeofence) ...[
                const SizedBox(width: 8),
                const Tooltip(
                  message:
                      'Sem geofence — o motor de avaliação não pode auditar '
                      'chegada/partida automaticamente.',
                  child: Icon(Icons.location_off,
                      size: 16, color: BusFlowColors.warning),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                z.address ?? 'Endereço não informado',
                style: BusFlowTypography.caption
                    .copyWith(color: BusFlowColors.textSecondary),
              ),
              Row(
                children: [
                  Icon(
                    hasGeofence ? Icons.my_location : Icons.location_off,
                    size: 12,
                    color: hasGeofence
                        ? BusFlowColors.success
                        : BusFlowColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    geoLabel,
                    style: BusFlowTypography.caption.copyWith(
                      color: hasGeofence
                          ? BusFlowColors.success
                          : BusFlowColors.warning,
                      fontFamily: hasGeofence ? 'monospace' : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                z.id.substring(0, 8),
                style: BusFlowTypography.caption.copyWith(
                    color: BusFlowColors.textDisabled,
                    fontFamily: 'monospace'),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Editar zona',
                color: BusFlowColors.textSecondary,
                onPressed: () async {
                  final saved =
                      await showZoneFormDialog(context, existingZone: z);
                  if (saved == true) ref.invalidate(operationalZonesProvider);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: BusFlowColors.border),
      ),
      child: Text(
        label,
        style: BusFlowTypography.caption
            .copyWith(color: BusFlowColors.textSecondary),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_outlined,
              size: 56, color: BusFlowColors.textDisabled),
          const SizedBox(height: 16),
          Text(
            'Nenhuma zona criada ainda',
            style: BusFlowTypography.sectionTitle
                .copyWith(color: BusFlowColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie zonas operacionais para usar como origem e destino\n'
            'nas viagens programadas por padrão de turno.',
            textAlign: TextAlign.center,
            style: BusFlowTypography.bodyMedium
                .copyWith(color: BusFlowColors.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Criar Primeira Zona'),
            onPressed: onCreateTap,
          ),
        ],
      ),
    );
  }
}

// ── Zone form dialog (create + edit) ─────────────────────────

class _ZoneFormDialog extends ConsumerStatefulWidget {
  final OperationalZone? existingZone;
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
  String? _errorMessage;

  // Nominatim address search state
  List<_PlaceSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _isSearching = false;

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
        final results = await _searchNominatim(query);
        if (mounted) {
          setState(() {
            _suggestions = results;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<List<_PlaceSuggestion>> _searchNominatim(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '5',
      'countrycodes': 'br',
      'addressdetails': '0',
    });
    final response = await http.get(uri, headers: {
      'User-Agent': 'BusFlow/1.0 (admin@busflow.app)',
      'Accept-Language': 'pt-BR,pt;q=0.9',
    });
    if (response.statusCode != 200) return [];
    final json = jsonDecode(response.body) as List;
    return json
        .map((e) => _PlaceSuggestion(
              displayName: e['display_name'] as String,
              lat: double.parse(e['lat'] as String),
              lng: double.parse(e['lon'] as String),
            ))
        .toList();
  }

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
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      if (orgId == null) {
        throw const DomainException('Sessão expirada. Faça login novamente.');
      }

      GeofenceConfiguration? geofence;
      if (_lat != null && _lng != null) {
        final radius = int.tryParse(_radiusController.text.trim()) ?? 200;
        geofence = GeofenceConfiguration(
          latitude: _lat!,
          longitude: _lng!,
          radiusMeters: radius,
        );
      }

      final OperationalZone zone;
      if (widget.existingZone != null) {
        // EDIT: reconstitute with existing ID (repo will UPDATE via UPSERT)
        zone = OperationalZone.reconstitute(
          id: widget.existingZone!.id,
          organizationId: orgId,
          name: _nameController.text.trim(),
          type: _selectedType,
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          geofence: geofence,
        );
      } else {
        // CREATE: new UUID generated by OperationalZone.create()
        zone = OperationalZone.create(
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
      if (mounted) Navigator.of(context).pop(true);
    } on DomainException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingZone != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isEdit),
              const Divider(height: 24, color: BusFlowColors.border),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 380,
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          child: _buildFormFields(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _buildMap()),
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
          color: BusFlowColors.primary,
        ),
        const SizedBox(width: 12),
        Text(
          isEdit ? 'Editar Zona Operacional' : 'Nova Zona Operacional',
          style: BusFlowTypography.sectionTitle,
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Tipo ──────────────────────────────────────────
        DropdownButtonFormField<ZoneType>(
          value: _selectedType,
          decoration: const InputDecoration(labelText: 'Tipo *'),
          items: ZoneType.values
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Row(children: [
                      Icon(t.icon, size: 18),
                      const SizedBox(width: 8),
                      Text(t.label),
                    ]),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedType = v!),
        ),
        const SizedBox(height: 16),

        // ── Nome ──────────────────────────────────────────
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Nome da Zona *',
            hintText: 'Ex: Garagem Central, Portaria Sul',
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
          autofocus: widget.existingZone == null,
        ),
        const SizedBox(height: 16),

        // ── Endereço com autocomplete Nominatim ───────────
        TextFormField(
          controller: _addressController,
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

        // Suggestions dropdown
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: BusFlowColors.surfaceElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: BusFlowColors.border),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              itemBuilder: (context, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined,
                      size: 16, color: BusFlowColors.primary),
                  title: Text(
                    s.displayName,
                    style: BusFlowTypography.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _selectSuggestion(s),
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // ── Geofence ──────────────────────────────────────
        const Divider(height: 24, color: BusFlowColors.border),
        Text(
          'GEOFENCE',
          style: BusFlowTypography.caption.copyWith(
            color: BusFlowColors.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),

        // Lat/lng — read-only display (never exposed as text fields)
        if (_lat != null && _lng != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: BusFlowColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: BusFlowColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.my_location,
                    size: 14, color: BusFlowColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: BusFlowColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() {
                        _lat = null;
                        _lng = null;
                      }),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Limpar',
                      style: TextStyle(
                          fontSize: 11, color: BusFlowColors.textSecondary)),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: BusFlowColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: BusFlowColors.warning.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.touch_app_outlined,
                    size: 16, color: BusFlowColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Busque um endereço ou clique no mapa para definir '
                    'as coordenadas do geofence.',
                    style:
                        TextStyle(fontSize: 11, color: BusFlowColors.warning),
                  ),
                ),
              ],
            ),
          ),

        // ── Raio ──────────────────────────────────────────
        TextFormField(
          controller: _radiusController,
          decoration: const InputDecoration(
            labelText: 'Raio de Detecção',
            suffixText: 'm',
            helperText:
                'Distância usada pelo motor para detectar chegada/partida.',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            if (_lat == null) return null; // geofence not set — no radius needed
            if (v == null || v.isEmpty) return 'Obrigatório com geofence';
            final n = int.tryParse(v);
            if (n == null || n <= 0 || n > 50000) return '1 a 50.000 m';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildMap() {
    final hasPin = _lat != null && _lng != null;
    final center =
        hasPin ? LatLng(_lat!, _lng!) : _defaultCenter;
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
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.busflow',
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
                        color: BusFlowColors.error,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: const Text('© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 9, color: Colors.black87)),
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
              color: BusFlowColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: BusFlowColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: BusFlowColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                        color: BusFlowColors.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => Navigator.of(context).pop(false),
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
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(isEdit ? Icons.save : Icons.add_location_alt,
                      size: 18),
              label: Text(isEdit ? 'Salvar Zona' : 'Criar Zona'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Place suggestion (Nominatim result) ──────────────────────

class _PlaceSuggestion {
  final String displayName;
  final double lat;
  final double lng;

  const _PlaceSuggestion({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
}
