import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../core/services/logger_service.dart';
import '../../../../../domain/entities/vehicle.dart';
import '../../../../../domain/enums/vehicle_status.dart';
import '../../../../../features/shared/providers.dart';
import '../../../providers/vehicles_provider.dart';
import '../../../../../domain/enums/user_role.dart';
import '../../../../../state/providers/auth_providers.dart';

class VehiclesTab extends ConsumerStatefulWidget {
  const VehiclesTab({super.key});

  @override
  ConsumerState<VehiclesTab> createState() => _VehiclesTabState();
}

class _VehiclesTabState extends ConsumerState<VehiclesTab> {
  bool _isDrawerOpen = false;
  String? _highlightedId;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _highlight(String id) {
    setState(() => _highlightedId = id);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredAsync = ref.watch(filteredVehiclesProvider);
    final userRole = ref.watch(currentUserRoleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, colorScheme, userRole),
              const SizedBox(height: 24),
              _buildSearchBar(),
              const SizedBox(height: 20),
              Expanded(
                child: filteredAsync.when(
                  data: (vehicles) => vehicles.isEmpty
                      ? _buildEmptyState()
                      : _buildTable(context, vehicles, colorScheme, userRole),
                  loading: () => _buildSkeleton(),
                  error: (err, stack) {
                    LoggerService().error(
                      'Falha ao carregar veículos',
                      error: err,
                      stackTrace: stack,
                    );
                    return _buildErrorState();
                  },
                ),
              ),
            ],
          ),
        ),
        if (_isDrawerOpen) ...[
          GestureDetector(
            onTap: () {},
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _VehicleFormDrawer(
              onClose: () => setState(() => _isDrawerOpen = false),
              onVehicleAdded: (id) {
                setState(() => _isDrawerOpen = false);
                _highlight(id);
                ref.invalidate(vehiclesListProvider);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    UserRole userRole,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.directions_bus,
            size: 28,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Frota de Veículos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cadastro de veículos operacionais vinculados à organização.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (userRole.hasPermission(UserRole.admin))
          FilledButton.icon(
            onPressed: () => setState(() => _isDrawerOpen = true),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Cadastrar veículo'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
      width: 400,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por placa ou modelo...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(vehiclesSearchQueryProvider.notifier).state = '';
                  },
                )
              : null,
          isDense: true,
        ),
        onChanged: (value) {
          ref.read(vehiclesSearchQueryProvider.notifier).state = value;
          setState(() {});
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_bus_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Nenhum veículo cadastrado ainda.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Clique em "Cadastrar veículo" para começar.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'Não foi possível carregar os veículos agora.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    List<Vehicle> vehicles,
    ColorScheme colorScheme,
    UserRole userRole,
  ) {
    return Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                _headerCell('PLACA', flex: 2),
                _headerCell('MODELO', flex: 2),
                _headerCell('CAPACIDADE', flex: 1),
                const SizedBox(
                  width: 110,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 80),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: vehicles.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final vehicle = vehicles[index];
                return _VehicleRow(
                  vehicle: vehicle,
                  isHighlighted: _highlightedId == vehicle.id,
                  onDelete: userRole.hasPermission(UserRole.admin)
                      ? () => _confirmDelete(context, vehicle)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: Text('Deseja excluir o veículo ${vehicle.plate} da frota?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref
            .read(vehicleAssetRepositoryProvider)
            .deleteVehicle(vehicle.id);
        ref.invalidate(vehiclesListProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Veículo removido com sucesso.')),
          );
        }
      } catch (e, stack) {
        LoggerService().error(
          'Falha ao remover veículo',
          error: e,
          stackTrace: stack,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível remover o veículo agora.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

// ── Vehicle Row ────────────────────────────────────────────────────────────
class _VehicleRow extends StatefulWidget {
  final Vehicle vehicle;
  final bool isHighlighted;
  final VoidCallback? onDelete;

  const _VehicleRow({
    required this.vehicle,
    required this.isHighlighted,
    required this.onDelete,
  });

  @override
  State<_VehicleRow> createState() => _VehicleRowState();
}

class _VehicleRowState extends State<_VehicleRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: widget.isHighlighted
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : _isHovered
              ? Colors.grey.shade50
              : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                widget.vehicle.plate,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                widget.vehicle.model ?? '—',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                '${widget.vehicle.capacity} pax',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ),
            SizedBox(
              width: 110,
              child: _VehicleStatusChip(status: widget.vehicle.status),
            ),
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onDelete != null)
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red.shade400,
                      ),
                      tooltip: 'Remover veículo',
                      onPressed: widget.onDelete,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status Chip ─────────────────────────────────────────────────────────────
class _VehicleStatusChip extends StatelessWidget {
  final VehicleStatus status;
  const _VehicleStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, bgColor) = switch (status) {
      VehicleStatus.available => (
        'Disponível',
        const Color(0xFF1B5E20),
        const Color(0xFFE8F5E9),
      ),
      VehicleStatus.inService => (
        'Em Serviço',
        const Color(0xFF1565C0),
        const Color(0xFFE3F2FD),
      ),
      VehicleStatus.maintenance => (
        'Manutenção',
        const Color(0xFFE65100),
        const Color(0xFFFFF3E0),
      ),
      VehicleStatus.retired => (
        'Aposentado',
        const Color(0xFF616161),
        const Color(0xFFF5F5F5),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Form Drawer ─────────────────────────────────────────────────────────────
class _VehicleFormDrawer extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String> onVehicleAdded;

  const _VehicleFormDrawer({
    required this.onClose,
    required this.onVehicleAdded,
  });

  @override
  ConsumerState<_VehicleFormDrawer> createState() => _VehicleFormDrawerState();
}

class _VehicleFormDrawerState extends ConsumerState<_VehicleFormDrawer>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  final _modelController = TextEditingController();
  final _capacityController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _plateController.dispose();
    _modelController.dispose();
    _capacityController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleClose() async {
    await _animController.reverse();
    widget.onClose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final vehicle = await ref
          .read(vehicleAssetRepositoryProvider)
          .addVehicle(
            plate: _plateController.text.trim(),
            model: _modelController.text.trim().isNotEmpty
                ? _modelController.text.trim()
                : null,
            capacity: int.parse(_capacityController.text.trim()),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Veículo cadastrado com sucesso'),
              ],
            ),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 3),
          ),
        );
        widget.onVehicleAdded(vehicle.id);
      }
    } catch (e, stack) {
      LoggerService().error(
        'Falha ao cadastrar veículo',
        error: e,
        stackTrace: stack,
      );
      String? msg;
      if (e is PostgrestException && e.code == 'P0001') {
        msg = e.message;
      } else if (e.toString().contains('uq_vehicles_org_plate')) {
        msg = 'Esta placa já está cadastrada na frota.';
      } else {
        msg = 'Não foi possível salvar o veículo agora. Tente novamente.';
      }
      setState(() {
        _errorMessage = msg;
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        elevation: 8,
        child: Container(
          width: 420,
          color: Colors.white,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.directions_bus,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Cadastrar veículo',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _handleClose,
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _fieldLabel('Placa'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _plateController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: ABC-1234',
                          ),
                          textCapitalization: TextCapitalization.characters,
                          enabled: !_isSaving,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'A placa é obrigatória';
                            }
                            final plate = v.trim().toUpperCase();
                            final br = RegExp(r'^[A-Z]{3}-[0-9]{4}$');
                            final mercosul = RegExp(
                              r'^[A-Z]{3}[0-9][A-Z][0-9]{2}$',
                            );
                            if (!br.hasMatch(plate) &&
                                !mercosul.hasMatch(plate)) {
                              return 'Use ABC-1234 (BR) ou ABC1D23 (Mercosul)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Modelo (opcional)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _modelController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: Mercedes-Benz O500',
                          ),
                          textCapitalization: TextCapitalization.words,
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Capacidade (passageiros)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _capacityController,
                          decoration: const InputDecoration(hintText: 'Ex: 48'),
                          keyboardType: TextInputType.number,
                          enabled: !_isSaving,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'A capacidade é obrigatória';
                            }
                            final n = int.tryParse(v.trim());
                            if (n == null || n < 0) {
                              return 'Informe um número válido';
                            }
                            return null;
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  size: 18,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : _handleClose,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _handleSubmit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Cadastrar',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade800,
      ),
    );
  }
}
