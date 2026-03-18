import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/services/logger_service.dart';
import '../../../../../domain/entities/transit_route.dart';
import '../../../../../features/shared/providers.dart';
import '../../../providers/routes_provider.dart';
import '../../../../../domain/enums/user_role.dart';
import '../../../../../state/providers/auth_providers.dart';

class RoutesTab extends ConsumerStatefulWidget {
  const RoutesTab({super.key});

  @override
  ConsumerState<RoutesTab> createState() => _RoutesTabState();
}

class _RoutesTabState extends ConsumerState<RoutesTab> {
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
    final filteredAsync = ref.watch(filteredRoutesProvider);
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
                  data: (routes) => routes.isEmpty
                      ? _buildEmptyState()
                      : _buildTable(context, routes, colorScheme, userRole),
                  loading: () => _buildSkeleton(),
                  error: (err, stack) {
                    LoggerService().error(
                      'Falha ao carregar rotas',
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
            child: _RouteFormDrawer(
              onClose: () => setState(() => _isDrawerOpen = false),
              onRouteAdded: (id) {
                setState(() => _isDrawerOpen = false);
                _highlight(id);
                ref.invalidate(routesListProvider);
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
          child: Icon(Icons.route, size: 28, color: colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rotas Operacionais',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cadastro de rotas vinculadas à operação da organização.',
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
            label: const Text('Cadastrar rota'),
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
          hintText: 'Buscar por nome curto ou nome completo...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(routesSearchQueryProvider.notifier).state = '';
                  },
                )
              : null,
          isDense: true,
        ),
        onChanged: (value) {
          ref.read(routesSearchQueryProvider.notifier).state = value;
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
              Icons.route_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Nenhuma rota cadastrada ainda.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Clique em "Cadastrar rota" para começar.',
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
            'Não foi possível carregar as rotas agora.',
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
    List<TransitRoute> routes,
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
                _headerCell('NOME CURTO', flex: 1),
                _headerCell('NOME COMPLETO', flex: 3),
                _headerCell('COR', flex: 1),
                const SizedBox(width: 80),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: routes.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final route = routes[index];
                return _RouteRow(
                  route: route,
                  isHighlighted: _highlightedId == route.id,
                  onDelete: userRole.hasPermission(UserRole.admin)
                      ? () => _confirmDelete(context, route)
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

  Future<void> _confirmDelete(BuildContext context, TransitRoute route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: Text('Deseja excluir a rota ${route.shortName}?'),
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
        await ref.read(transitRouteRepositoryProvider).deleteRoute(route.id);
        ref.invalidate(routesListProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rota removida com sucesso.')),
          );
        }
      } catch (e, stack) {
        LoggerService().error(
          'Falha ao remover rota',
          error: e,
          stackTrace: stack,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível remover a rota agora.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

// ── Route Row ───────────────────────────────────────────────────────────────
class _RouteRow extends StatefulWidget {
  final TransitRoute route;
  final bool isHighlighted;
  final VoidCallback? onDelete;

  const _RouteRow({
    required this.route,
    required this.isHighlighted,
    required this.onDelete,
  });

  @override
  State<_RouteRow> createState() => _RouteRowState();
}

class _RouteRowState extends State<_RouteRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final routeColor = _parseColor(widget.route.color);

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
              flex: 1,
              child: Text(
                widget.route.shortName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                widget.route.longName,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ),
            Expanded(
              flex: 1,
              child: routeColor != null
                  ? Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: routeColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.route.color ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '—',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade400,
                      ),
                    ),
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
                      tooltip: 'Remover rota',
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

  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return null;
    }
  }
}

// ── Form Drawer ─────────────────────────────────────────────────────────────
class _RouteFormDrawer extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String> onRouteAdded;

  const _RouteFormDrawer({required this.onClose, required this.onRouteAdded});

  @override
  ConsumerState<_RouteFormDrawer> createState() => _RouteFormDrawerState();
}

class _RouteFormDrawerState extends ConsumerState<_RouteFormDrawer>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _shortNameController = TextEditingController();
  final _longNameController = TextEditingController();
  final _colorController = TextEditingController();
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
    _shortNameController.dispose();
    _longNameController.dispose();
    _colorController.dispose();
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
      final route = await ref
          .read(transitRouteRepositoryProvider)
          .addRoute(
            shortName: _shortNameController.text.trim(),
            longName: _longNameController.text.trim(),
            color: _colorController.text.trim().isNotEmpty
                ? _colorController.text.trim()
                : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Rota cadastrada com sucesso'),
              ],
            ),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 3),
          ),
        );
        widget.onRouteAdded(route.id);
      }
    } catch (e, stack) {
      LoggerService().error(
        'Falha ao cadastrar rota',
        error: e,
        stackTrace: stack,
      );
      setState(() {
        _errorMessage =
            'Não foi possível salvar a rota agora. Tente novamente.';
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
                        Icons.route,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Cadastrar rota',
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
                        _fieldLabel('Nome curto'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _shortNameController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: L001',
                          ),
                          textCapitalization: TextCapitalization.characters,
                          enabled: !_isSaving,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'O nome curto é obrigatório';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Nome completo'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _longNameController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: Terminal Central → Zona Norte',
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          enabled: !_isSaving,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'O nome completo é obrigatório';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Cor (hex, opcional)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _colorController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: #3F51B5',
                          ),
                          enabled: !_isSaving,
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
