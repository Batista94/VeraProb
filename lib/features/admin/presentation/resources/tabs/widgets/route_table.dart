import 'package:flutter/material.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// Parses a hex color string to a Flutter [Color].
///
/// Accepts formats like `#3F51B5` or `3F51B5`. Returns `null` on failure.
Color? parseRouteColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return null;
  }
}

/// Table displaying the list of transit routes.
class RouteTable extends StatelessWidget {
  final List<TransitRoute> routes;
  final String? highlightedId;
  final UserRole userRole;
  final Future<void> Function(TransitRoute) onDeleteRequested;

  const RouteTable({
    super.key,
    required this.routes,
    required this.highlightedId,
    required this.userRole,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
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
                return RouteRow(
                  route: route,
                  isHighlighted: highlightedId == route.id,
                  onDelete: userRole.hasPermission(UserRole.admin)
                      ? () => onDeleteRequested(route)
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
}

/// A single route row with hover effect and color display.
class RouteRow extends StatefulWidget {
  final TransitRoute route;
  final bool isHighlighted;
  final VoidCallback? onDelete;

  const RouteRow({
    super.key,
    required this.route,
    required this.isHighlighted,
    required this.onDelete,
  });

  @override
  State<RouteRow> createState() => _RouteRowState();
}

class _RouteRowState extends State<RouteRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final routeColor = parseRouteColor(widget.route.color);

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
}
