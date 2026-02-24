import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';

/// Navigation destinations for the admin icon sidebar.
enum AdminDestination {
  commandCenter(
    icon: Icons.radar_outlined,
    selectedIcon: Icons.radar,
    label: 'Controle',
    tooltip: 'Centro de Controle',
  ),
  trips(
    icon: Icons.timeline_outlined,
    selectedIcon: Icons.timeline,
    label: 'Viagens',
    tooltip: 'Timeline de Viagens',
  ),
  resources(
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    label: 'Recursos',
    tooltip: 'Motoristas, Veículos, Rotas',
  ),
  system(
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart,
    label: 'Sistema',
    tooltip: 'Saúde do Sistema',
  ),
  audit(
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    label: 'Auditoria',
    tooltip: 'Auditoria OCC',
  );

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String tooltip;

  const AdminDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.tooltip,
  });
}

/// State provider for the currently selected admin destination.
final adminDestinationProvider = StateProvider<AdminDestination>(
  (ref) => AdminDestination.commandCenter,
);

/// The master layout shell for the admin panel.
///
/// Layout structure:
/// ┌──────────────────────────────────────────────────────┐
/// │  TOP BAR (48px) — logo, feed status, clock           │
/// ├────┬─────────────────────────────────────────────────┤
/// │SIDE│                                                 │
/// │BAR │              CONTENT AREA                       │
/// │56px│        (changes per destination)                │
/// │    │                                                 │
/// └────┴─────────────────────────────────────────────────┘
class AdminShell extends ConsumerWidget {
  final Map<AdminDestination, Widget> screens;

  const AdminShell({super.key, required this.screens});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDestination = ref.watch(adminDestinationProvider);

    return Scaffold(
      backgroundColor: BusFlowColors.background,
      body: Column(
        children: [
          // ── Top Bar ──────────────────────────────────────
          _TopBar(currentDestination: currentDestination),

          // ── Body: Sidebar + Content ──────────────────────
          Expanded(
            child: Row(
              children: [
                // ── Icon Sidebar (56px) ────────────────────
                _IconSidebar(
                  currentDestination: currentDestination,
                  onDestinationSelected: (dest) {
                    ref.read(adminDestinationProvider.notifier).state = dest;
                  },
                ),

                // ── Vertical Divider ───────────────────────
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: BusFlowColors.border,
                ),

                // ── Content Area ───────────────────────────
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child:
                        screens[currentDestination] ??
                        const Center(child: Text('Em construção')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Top bar with logo, system status indicators, and clock.
class _TopBar extends StatelessWidget {
  final AdminDestination currentDestination;

  const _TopBar({required this.currentDestination});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: BusFlowColors.surface,
        border: Border(
          bottom: BorderSide(color: BusFlowColors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Logo + Title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: BusFlowColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_bus,
                  color: BusFlowColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Text(
                  'BUSFLOW',
                  style: TextStyle(
                    color: BusFlowColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Text(
            currentDestination.tooltip.toUpperCase(),
            style: BusFlowTypography.caption.copyWith(
              letterSpacing: 1.0,
              color: BusFlowColors.textSecondary,
            ),
          ),

          const Spacer(),

          // Feed status indicator
          _StatusPill(icon: Icons.cell_tower, label: 'Feed', isOnline: true),

          const SizedBox(width: 12),

          // Live clock
          _LiveClock(),
        ],
      ),
    );
  }
}

/// Small status pill showing online/offline state.
class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isOnline;

  const _StatusPill({
    required this.icon,
    required this.label,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? BusFlowColors.onTime : BusFlowColors.critical;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: BusFlowTypography.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// A ticking clock widget showing current time.
class _LiveClock extends StatefulWidget {
  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late Stream<DateTime> _timeStream;

  @override
  void initState() {
    super.initState();
    _timeStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: _timeStream,
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final hours = now.hour.toString().padLeft(2, '0');
        final minutes = now.minute.toString().padLeft(2, '0');
        final seconds = now.second.toString().padLeft(2, '0');

        return Text(
          '$hours:$minutes:$seconds',
          style: const TextStyle(
            fontFamily: 'Roboto Mono, monospace',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: BusFlowColors.textPrimary,
            letterSpacing: 1.0,
          ),
        );
      },
    );
  }
}

/// The 56px icon sidebar with navigation destinations.
class _IconSidebar extends StatelessWidget {
  final AdminDestination currentDestination;
  final ValueChanged<AdminDestination> onDestinationSelected;

  const _IconSidebar({
    required this.currentDestination,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      color: BusFlowColors.surface,
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Navigation icons
          ...AdminDestination.values.map((dest) {
            final isSelected = dest == currentDestination;
            return _SidebarIcon(
              icon: isSelected ? dest.selectedIcon : dest.icon,
              tooltip: dest.tooltip,
              isSelected: isSelected,
              onTap: () => onDestinationSelected(dest),
            );
          }),

          const Spacer(),

          // Settings / profile at bottom
          _SidebarIcon(
            icon: Icons.settings_outlined,
            tooltip: 'Configurações',
            isSelected: false,
            onTap: () {
              // TODO: Settings screen
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A single icon button in the sidebar.
class _SidebarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarIcon({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      verticalOffset: 0,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 48,
          decoration: BoxDecoration(
            color: isSelected
                ? BusFlowColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? BusFlowColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isSelected
                ? BusFlowColors.primary
                : BusFlowColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
