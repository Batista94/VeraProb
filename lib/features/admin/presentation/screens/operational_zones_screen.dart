import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/presentation/shared/widgets/veraprob_header.dart';
import 'package:veraprob/presentation/shared/widgets/veraprob_chip.dart';

// ── Public API ───────────────────────────────────────────────

/// Opens the zone create/edit dialog.
/// Returns the saved [OperationalZone] on success, null on cancel.
Future<OperationalZone?> showZoneFormDialog(
  BuildContext context, {
  OperationalZone? existingZone,
}) {
  return showDialog<OperationalZone>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ZoneFormDialog(existingZone: existingZone),
  );
}

// ── ZoneType extensions ──────────────────────────────────────

extension ZoneTypeUi on ZoneType {
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
          VeraProbHeader(
            icon: Icons.place_outlined,
            title: 'Zonas Operacionais',
            subtitle: 'Garagens, clientes e pontos de apoio.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nova Zona Operacional'),
                onPressed: () async {
                  final saved = await showZoneFormDialog(context);
                  if (saved != null) ref.invalidate(operationalZonesProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: VeraProbSpacing.md),
          Text(
            'Garagens, clientes e pontos de apoio usados como origem/destino '
            'nas viagens programadas. Geofence (coordenadas + raio) é obrigatório '
            'para auditoria automática pelo motor de avaliação.',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: zonesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar zonas: $e',
                  style: VeraProbTypography.bodyMedium.copyWith(
                    color: VeraProbColors.error,
                  ),
                ),
              ),
              data: (zones) => zones.isEmpty
                  ? _EmptyState(
                      onCreateTap: () async {
                        final saved = await showZoneFormDialog(context);
                        if (saved != null) {
                          ref.invalidate(operationalZonesProvider);
                        }
                      },
                    )
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
          const Divider(height: 1, color: VeraProbColors.border),
      itemBuilder: (context, i) {
        final z = zones[i];
        final hasGeofence = z.geofence != null;
        final geoLabel = hasGeofence
            ? '${z.geofence!.radiusMeters} m  ·  '
                  '${z.geofence!.latitude.toStringAsFixed(5)}, '
                  '${z.geofence!.longitude.toStringAsFixed(5)}'
            : 'Sem geofence — configure para auditoria automática';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: VeraProbColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(z.type.icon, color: VeraProbColors.primary, size: 20),
          ),
          title: Row(
            children: [
              Text(z.name, style: VeraProbTypography.kpiLabel),
              const SizedBox(width: 8),
              _TypeChip(label: z.type.label),
              if (!hasGeofence) ...[
                const SizedBox(width: 8),
                const Tooltip(
                  message:
                      'Sem geofence — o motor de avaliação não pode auditar '
                      'chegada/partida automaticamente.',
                  child: Icon(
                    Icons.location_off,
                    size: 16,
                    color: VeraProbColors.warning,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                z.address ?? 'Endereço não informado',
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.textSecondary,
                ),
              ),
              Row(
                children: [
                  Icon(
                    hasGeofence ? Icons.my_location : Icons.location_off,
                    size: 12,
                    color: hasGeofence
                        ? VeraProbColors.success
                        : VeraProbColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    geoLabel,
                    style: VeraProbTypography.caption.copyWith(
                      color: hasGeofence
                          ? VeraProbColors.success
                          : VeraProbColors.warning,
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
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.textDisabled,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Editar zona',
                color: VeraProbColors.textSecondary,
                onPressed: () async {
                  final saved = await showZoneFormDialog(
                    context,
                    existingZone: z,
                  );
                  if (saved != null) ref.invalidate(operationalZonesProvider);
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
    return VeraProbChip(
      label: label,
      color: VeraProbColors.primary,
      outline: true,
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
          const Icon(
            Icons.place_outlined,
            size: 56,
            color: VeraProbColors.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma zona criada ainda',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie zonas operacionais para usar como origem e destino\n'
            'nas viagens programadas por padrão de turno.',
            textAlign: TextAlign.center,
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
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
  final _contractorLabelController = TextEditingController();
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
  final FocusNode _contractorLabelFocus = FocusNode();
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
      _contractorLabelController.text = zone.contractorLabel ?? '';
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
    _contractorLabelController.dispose();
    _addressController.dispose();
    _radiusController.dispose();
    _nameFocus.dispose();
    _contractorLabelFocus.dispose();
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
    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'veraprob/1.0 (admin@veraprob.app)',
        'Accept-Language': 'pt-BR,pt;q=0.9',
      },
    );
    if (response.statusCode != 200) return [];
    final json = jsonDecode(response.body) as List;
    return json
        .map(
          (e) => _PlaceSuggestion(
            displayName: e['display_name'] as String,
            lat: double.parse(e['lat'] as String),
            lng: double.parse(e['lon'] as String),
          ),
        )
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

      final contractorLabel = _contractorLabelController.text.trim().isEmpty
          ? null
          : _contractorLabelController.text.trim();

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
          contractorLabel: contractorLabel,
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
          contractorLabel: contractorLabel,
          geofence: geofence,
        );
      }

      await saveZone(zone, ref);
      if (!mounted || _isCancelled) return;
      Navigator.of(context).pop(zone);
    } on DomainException catch (e) {
      if (!mounted || _isCancelled) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted || _isCancelled) return;
      setState(() => _errorMessage = 'Erro inesperado: $e');
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
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 680),
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

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Tipo ──────────────────────────────────────────
        DropdownButtonFormField<ZoneType>(
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
        ),
        const SizedBox(height: 16),

        // ── Nome ──────────────────────────────────────────
        TextFormField(
          controller: _nameController,
          focusNode: _nameFocus,
          decoration: const InputDecoration(
            labelText: 'Nome da Zona *',
            hintText: 'Ex: Garagem Central, Portaria Sul',
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
          autofocus: widget.existingZone == null,
          onFieldSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_contractorLabelFocus),
        ),
        const SizedBox(height: 16),

        // ── Contratante / Cliente ──────────────────────────
        Builder(
          builder: (context) {
            final options =
                ref.watch(contractorNamesProvider).valueOrNull ??
                const <String>[];
            return Autocomplete<String>(
              initialValue: TextEditingValue(
                text: _contractorLabelController.text,
              ),
              optionsBuilder: (v) {
                if (v.text.isEmpty) return options;
                final lower = v.text.toLowerCase();
                return options.where((n) => n.toLowerCase().contains(lower));
              },
              displayStringForOption: (o) => o,
              fieldViewBuilder: (ctx, ctrl, focusNode, onSubmitted) {
                ctrl.addListener(
                  () => _contractorLabelController.text = ctrl.text,
                );
                return TextFormField(
                  controller: ctrl,
                  focusNode: _contractorLabelFocus,
                  decoration: const InputDecoration(
                    labelText: 'Contratante / Cliente (opcional)',
                    hintText: 'Ex: Empresa ABC',
                    helperText:
                        'Agrupa esta zona no Wizard de Plano para o contratante informado.',
                  ),
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_addressFocus),
                );
              },
              onSelected: (v) {
                _contractorLabelController.text = v;
                setState(() {});
              },
            );
          },
        ),
        const SizedBox(height: 16),

        // ── Endereço com autocomplete Nominatim ───────────
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

        // Suggestions dropdown
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

        const SizedBox(height: 16),

        // G2 — Geofence ExpansionTile
        ExpansionTile(
          leading: Icon(
            Icons.radar,
            color: _lat != null
                ? VeraProbColors.success
                : VeraProbColors.textSecondary,
          ),
          title: const Text('Configuração de Geofence'),
          subtitle: Text(
            _lat != null ? 'Configurado' : 'Não configurado',
            style: TextStyle(
              color: _lat != null
                  ? VeraProbColors.success
                  : VeraProbColors.textSecondary,
              fontSize: 12,
            ),
          ),
          initiallyExpanded: _lat != null,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Lat/lng — read-only display
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
                          color: VeraProbColors.success.withValues(
                            alpha: 0.35,
                          ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
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
                              'Busque um endereço ou clique no mapa para '
                              'definir as coordenadas do geofence.',
                              style: TextStyle(
                                fontSize: 11,
                                color: VeraProbColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Raio ────────────────────────────────
                  TextFormField(
                    controller: _radiusController,
                    focusNode: _radiusFocus,
                    decoration: const InputDecoration(
                      labelText: 'Raio de Detecção',
                      suffixText: 'm',
                      helperText:
                          'Distância usada pelo motor para detectar chegada/partida.',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (_lat == null) return null;
                      if (v == null || v.isEmpty) {
                        return 'Obrigatório com geofence';
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
        ),
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
