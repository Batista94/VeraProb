import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/admin/route_command_service_provider.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'package:veraprob/features/admin/providers/routes_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

import 'widgets/route_empty_state.dart';
import 'widgets/route_form_drawer.dart';
import 'widgets/route_search_bar.dart';
import 'widgets/route_skeleton.dart';
import 'widgets/route_tab_header.dart';
import 'widgets/route_table.dart';

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

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RouteTabHeader(
                userRole: userRole,
                onAddPressed: () => setState(() => _isDrawerOpen = true),
              ),
              const SizedBox(height: 24),
              RouteSearchBar(
                controller: _searchController,
                onChanged: () {
                  ref
                      .read(routesSearchQueryProvider.notifier)
                      .set(_searchController.text);
                  setState(() {});
                },
                onClear: () {
                  _searchController.clear();
                  ref.read(routesSearchQueryProvider.notifier).set('');
                  setState(() {});
                },
              ),
              const SizedBox(height: 20),
              Expanded(
                child: switch (filteredAsync) {
                  AsyncData(:final value) =>
                    value.isEmpty
                        ? const RouteEmptyState()
                        : _buildTable(value, userRole),
                  AsyncLoading() => const RouteSkeleton(),
                  AsyncError(:final error) => () {
                    LoggerService().error(
                      'Falha ao carregar rotas',
                      error: error,
                    );
                    return _buildErrorState();
                  }(),
                },
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
            child: RouteFormDrawer(
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

  Widget _buildTable(List<TransitRoute> routes, UserRole userRole) {
    return RouteTable(
      routes: routes,
      highlightedId: _highlightedId,
      userRole: userRole,
      onDeleteRequested: (route) => _confirmDelete(context, route),
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
        await ref.read(routeCommandServiceProvider).deleteRoute(route.id);
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
