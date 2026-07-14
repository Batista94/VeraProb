import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/features/admin/providers/drivers_provider.dart';
import 'package:veraprob/features/admin/presentation/widgets/universal_csv_importer.dart';
import 'widgets/driver_form_drawer.dart';
import 'widgets/telegram_binding_dialog.dart';

class DriversScreen extends ConsumerStatefulWidget {
  const DriversScreen({super.key});

  @override
  ConsumerState<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends ConsumerState<DriversScreen> {
  bool _isDrawerOpen = false;
  String? _highlightedDriverId;
  bool _showArchived = false;
  final _searchController = TextEditingController();

  List<Driver> _filterDrivers(List<Driver> drivers) {
    final q = _searchController.text.toLowerCase();
    return drivers.where((d) {
      if (!_showArchived && d.isArchived) return false;
      if (q.isEmpty) return true;
      return d.name.toLowerCase().contains(q) || d.licenseNumber.contains(q);
    }).toList();
  }

  void _openDrawer() {
    setState(() => _isDrawerOpen = true);
  }

  void _closeDrawer() {
    setState(() => _isDrawerOpen = false);
  }

  void _highlightDriver(String id) {
    setState(() => _highlightedDriverId = id);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightedDriverId = null);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(driversListProvider);
    final filteredAsync = switch (driversAsync) {
      AsyncData(:final value) => AsyncData(_filterDrivers(value)),
      AsyncError(:final error, :final stackTrace) => AsyncError<List<Driver>>(
        error,
        stackTrace,
      ),
      _ => const AsyncLoading<List<Driver>>(),
    };
    final userRole = ref.watch(currentUserRoleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Main content
        Padding(
          padding: const EdgeInsets.all(VeraProbSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(context, colorScheme, userRole),
              const SizedBox(height: VeraProbSpacing.lg),
              // Search bar
              _buildSearchBar(context),
              const SizedBox(height: 20),
              // Drivers table
              Expanded(
                child: switch (filteredAsync) {
                  AsyncData(:final value) =>
                    value.isEmpty
                        ? const EmptyState(
                            icon: Icons.people_outline,
                            title: 'Nenhum motorista cadastrado ainda.',
                            description:
                                'Clique em "Cadastrar motorista" para começar.',
                          )
                        : _buildDriversTable(
                            context,
                            value,
                            colorScheme,
                            userRole,
                          ),
                  AsyncLoading() => const SkeletonListLoader(),
                  AsyncError(:final error) => _buildDriversError(error),
                },
              ),
            ],
          ),
        ),
        // Drawer overlay
        if (_isDrawerOpen) ...[
          // Backdrop
          GestureDetector(
            onTap: () {}, // Prevent accidental close
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
          // Drawer panel
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: DriverFormDrawer(
              onClose: _closeDrawer,
              onDriverAdded: (id) {
                _closeDrawer();
                _highlightDriver(id);
                ref.invalidate(driversListProvider);
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
    final showArchived = _showArchived;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: VeraProbRadii.lgAll,
          ),
          child: Icon(Icons.people_alt, size: 28, color: colorScheme.primary),
        ),
        const SizedBox(width: VeraProbSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Motoristas da Frota',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: VeraProbSpacing.xs),
              Text(
                'Cadastro administrativo dos motoristas vinculados à operação.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: VeraProbSpacing.md),
        // Toggle: show archived drivers (supervisors can audit history — INV-3)
        TextButton.icon(
          onPressed: () {
            setState(() => _showArchived = !_showArchived);
          },
          icon: Icon(
            showArchived ? Icons.visibility_off_outlined : Icons.history,
            size: 18,
            color: showArchived
                ? VeraProbColors.warning
                : VeraProbColors.textSecondary,
          ),
          label: Text(
            showArchived ? 'Ocultar arquivados' : 'Ver arquivados',
            style: TextStyle(
              fontSize: 13,
              color: showArchived
                  ? VeraProbColors.warning
                  : VeraProbColors.textSecondary,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_outlined),
          tooltip: 'Importar CSV',
          onPressed: () async {
            final imported = await showUniversalCsvImporter(
              context,
              targetEntity: 'operator',
            );
            if (imported) ref.invalidate(driversListProvider);
          },
        ),
        const SizedBox(width: VeraProbSpacing.sm),
        if (userRole.hasPermission(UserRole.admin))
          FilledButton.icon(
            onPressed: _openDrawer,
            icon: const Icon(Icons.person_add_alt_1, size: 20),
            label: const Text('Cadastrar motorista'),
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

  Widget _buildSearchBar(BuildContext context) {
    return SizedBox(
      width: 400,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nome ou CNH...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildDriversError(Object error) {
    LoggerService().error('Falha ao carregar motoristas', error: error);
    return const EmptyState(
      icon: Icons.error_outline,
      title: 'Não foi possível carregar os motoristas agora.',
      description: 'Tente novamente mais tarde.',
    );
  }

  Widget _buildDriversTable(
    BuildContext context,
    List<Driver> drivers,
    ColorScheme colorScheme,
    UserRole userRole,
  ) {
    return Card(
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: VeraProbColors.border)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 52), // Avatar space
                Expanded(flex: 3, child: _TableHeaderLabel('NOME')),
                Expanded(flex: 2, child: _TableHeaderLabel('CNH')),
                SizedBox(width: 100, child: _TableHeaderLabel('STATUS')),
                SizedBox(width: 116), // Actions space
              ],
            ),
          ),
          // Table rows
          Expanded(
            child: ListView.separated(
              itemCount: drivers.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: VeraProbColors.border),
              itemBuilder: (context, index) {
                final driver = drivers[index];
                final isHighlighted = _highlightedDriverId == driver.id;

                final orgId = ref.read(currentOrganizationIdProvider) ?? '';
                return _DriverRow(
                  driver: driver,
                  isHighlighted: isHighlighted,
                  organizationId: orgId,
                  onArchive:
                      (userRole.hasPermission(UserRole.admin) &&
                          !driver.isArchived)
                      ? () => _confirmArchive(context, driver)
                      : null,
                  onTelegramBind:
                      (userRole.hasPermission(UserRole.operator) &&
                          !driver.isArchived)
                      ? () => showDialog<void>(
                          context: context,
                          builder: (_) => TelegramBindingDialog(
                            driverId: driver.id,
                            driverName: driver.name,
                            organizationId: orgId,
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context, Driver driver) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arquivar motorista'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Arquivar ${driver.name}?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            const Text(
              'O motorista será inativado e o vínculo do Telegram será revogado. '
              'Evidências e histórico forense são preservados (INV-3).',
              style: TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.warning,
              // ACCENT-FILL-CONTRAST: dark foreground on accent fill.
              foregroundColor: VeraProbColors.background,
            ),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: const Text('Arquivar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(driverRepositoryProvider).archiveDriver(driver.id);
        ref.invalidate(driversListProvider);
        messenger.showSnackBar(
          SnackBar(
            content: Text('${driver.name} arquivado. Histórico preservado.'),
          ),
        );
      } catch (e, stack) {
        LoggerService().error(
          'Falha ao arquivar motorista',
          error: e,
          stackTrace: stack,
        );
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível arquivar o motorista. Tente novamente.',
            ),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Table Header Label
// ---------------------------------------------------------------------------
class _TableHeaderLabel extends StatelessWidget {
  final String label;
  const _TableHeaderLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: VeraProbColors.textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Driver Row Widget
// ---------------------------------------------------------------------------
class _DriverRow extends StatefulWidget {
  final Driver driver;
  final bool isHighlighted;
  final String organizationId;
  final VoidCallback? onArchive;
  final VoidCallback? onTelegramBind;

  const _DriverRow({
    required this.driver,
    required this.isHighlighted,
    required this.organizationId,
    required this.onArchive,
    required this.onTelegramBind,
  });

  @override
  State<_DriverRow> createState() => _DriverRowState();
}

class _DriverRowState extends State<_DriverRow> {
  bool _isHovered = false;

  Color _rowColor(ColorScheme colorScheme, bool isArchived) {
    if (widget.isHighlighted) {
      return colorScheme.primaryContainer.withValues(alpha: 0.3);
    }
    if (isArchived) {
      return VeraProbColors.surfaceElevated.withValues(alpha: 0.5);
    }
    if (_isHovered) return VeraProbColors.surfaceElevated;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isArchived = widget.driver.isArchived;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(color: _rowColor(colorScheme, isArchived)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Opacity(
          opacity: isArchived ? 0.55 : 1.0,
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 18,
                backgroundColor: isArchived
                    ? VeraProbColors.surfaceElevated
                    : colorScheme.primaryContainer,
                child: Text(
                  widget.driver.name[0].toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isArchived
                        ? VeraProbColors.textDisabled
                        : colorScheme.primary,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: VeraProbSpacing.md),
              // Name
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Text(
                      widget.driver.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        decoration: isArchived
                            ? TextDecoration.lineThrough
                            : null,
                        color: isArchived ? VeraProbColors.textDisabled : null,
                      ),
                    ),
                    if (isArchived) ...[
                      const SizedBox(width: 6),
                      const Tooltip(
                        message: 'Arquivado — histórico forense preservado',
                        child: Icon(
                          Icons.archive_outlined,
                          size: 14,
                          color: VeraProbColors.textDisabled,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // CNH
              Expanded(
                flex: 2,
                child: Text(
                  widget.driver.licenseNumber,
                  style: VeraProbTypography.mono(
                    size: 14,
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ),
              // Status chip
              SizedBox(
                width: 100,
                child: _StatusChip(
                  status: widget.driver.status,
                  isArchived: isArchived,
                ),
              ),
              // Actions
              SizedBox(
                width: 116,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.onTelegramBind != null)
                      IconButton(
                        icon: const Icon(
                          Icons.telegram,
                          size: 20,
                          color: VeraProbColors.info,
                        ),
                        tooltip: 'Vincular Telegram',
                        onPressed: widget.onTelegramBind,
                      ),
                    if (widget.onArchive != null)
                      IconButton(
                        icon: const Icon(
                          Icons.archive_outlined,
                          size: 20,
                          color: VeraProbColors.warning,
                        ),
                        tooltip: 'Arquivar motorista',
                        onPressed: widget.onArchive,
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
}

// ---------------------------------------------------------------------------
// Status Chip Widget
// ---------------------------------------------------------------------------
class _StatusChip extends StatelessWidget {
  final DriverStatus status;
  final bool isArchived;
  const _StatusChip({required this.status, this.isArchived = false});

  @override
  Widget build(BuildContext context) {
    // Archived supersedes active/pending status for display purposes (INV-3).
    final (label, color) = isArchived
        ? ('Arquivado', VeraProbColors.textDisabled)
        : switch (status) {
            DriverStatus.active => ('Ativo', VeraProbColors.success),
            DriverStatus.inactive => ('Inativo', VeraProbColors.textSecondary),
            DriverStatus.pending => ('Pendente', VeraProbColors.warning),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VeraProbRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
