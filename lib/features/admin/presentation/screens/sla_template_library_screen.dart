import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';
import 'package:veraprob/features/admin/presentation/widgets/sla_template_card.dart';
import 'sla_template_editor_dialog.dart';

/// SLA Template Library screen with two sections:
/// 1. "Modelos do Sistema" (read-only presets, clone-only)
/// 2. "Meus Modelos" (org-owned, full CRUD)
class SlaTemplateLibraryScreen extends ConsumerStatefulWidget {
  const SlaTemplateLibraryScreen({super.key});

  @override
  ConsumerState<SlaTemplateLibraryScreen> createState() =>
      _SlaTemplateLibraryScreenState();
}

class _SlaTemplateLibraryScreenState
    extends ConsumerState<SlaTemplateLibraryScreen> {
  TransportVertical? _filterVertical;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(slaTemplatePresetsProvider);
    final orgTemplatesAsync = ref.watch(slaTemplatesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(VeraProbSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: VeraProbSpacing.sm),
            Text(
              'Gerencie modelos SLA reutilizáveis para configuração rápida de contratos.',
              style: VeraProbTypography.bodyMedium.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            _buildFilters(),
            const SizedBox(height: VeraProbSpacing.lg),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'Modelos do Sistema',
                      count: _filteredPresets(presets).length,
                    ),
                    const SizedBox(height: 12),
                    _buildGrid(_filteredPresets(presets), isPreset: true),
                    const SizedBox(height: 32),
                    _SectionHeader(
                      title: 'Meus Modelos',
                      count: switch (orgTemplatesAsync) {
                        AsyncData(:final value) => _filteredTemplates(
                          value,
                        ).length,
                        _ => null,
                      },
                    ),
                    const SizedBox(height: 12),
                    switch (orgTemplatesAsync) {
                      AsyncData(:final value) => _buildMyModelsSection(
                        value,
                        context,
                      ),
                      AsyncLoading() => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      AsyncError() => const Center(
                        child: Text(
                          'Não foi possível carregar os modelos de SLA.',
                          style: TextStyle(color: VeraProbColors.error),
                        ),
                      ),
                    },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo Modelo'),
        backgroundColor: VeraProbColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          Icons.library_books_outlined,
          size: 28,
          color: VeraProbColors.primary,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            'Biblioteca de Modelos SLA',
            style: VeraProbTypography.sectionTitle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar por nome...',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        DropdownButton<TransportVertical?>(
          value: _filterVertical,
          hint: const Text('Todas as verticais'),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem(child: Text('Todas')),
            ...TransportVertical.values.map(
              (v) => DropdownMenuItem(value: v, child: Text(v.label)),
            ),
          ],
          onChanged: (v) => setState(() => _filterVertical = v),
        ),
      ],
    );
  }

  List<SlaTemplateView> _filteredPresets(List<SlaTemplateView> presets) {
    return _applyFilters(presets);
  }

  List<SlaTemplateView> _filteredTemplates(List<SlaTemplateView> templates) {
    return _applyFilters(templates);
  }

  List<SlaTemplateView> _applyFilters(List<SlaTemplateView> list) {
    var result = list;
    if (_filterVertical != null) {
      result = result.where((t) => t.vertical == _filterVertical).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result
          .where((t) => t.name.toLowerCase().contains(query))
          .toList();
    }
    return result;
  }

  Widget _buildGrid(List<SlaTemplateView> templates, {required bool isPreset}) {
    if (templates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Nenhum modelo encontrado.',
          style: VeraProbTypography.bodySmall,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 3
            : constraints.maxWidth > 650
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.35,
          ),
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final t = templates[index];
            return SlaTemplateCard(
              template: t,
              onClone: () => _cloneTemplate(t),
              onEdit: isPreset ? null : () => _showEditor(context, existing: t),
              onDelete: isPreset ? null : () => _confirmDelete(t),
            );
          },
        );
      },
    );
  }

  Widget _buildMyModelsSection(
    List<SlaTemplateView> value,
    BuildContext context,
  ) {
    final filtered = _filteredTemplates(value);
    if (filtered.isEmpty) {
      return _EmptyState(onCreate: () => _showEditor(context));
    }
    return _buildGrid(filtered, isPreset: false);
  }

  Future<void> _showEditor(
    BuildContext context, {
    SlaTemplateView? existing,
  }) async {
    final saved = await showSlaTemplateEditorDialog(
      context,
      existing: existing,
    );
    if (saved != null) {
      ref.invalidate(slaTemplatesProvider);
    }
  }

  Future<void> _cloneTemplate(SlaTemplateView source) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      if (orgId == null) return;
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      final cloneDomain = await ref
          .read(cloneSlaTemplateHandlerProvider)
          .handle(
            sourceId: source.id,
            organizationId: orgId,
            sessionId: sessionId,
          );

      final clone = SlaTemplateView.fromDomain(cloneDomain);
      ref.invalidate(slaTemplatesProvider);

      messenger.showSnackBar(
        SnackBar(
          content: Text('Modelo "${clone.name}" criado com sucesso.'),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível clonar o modelo. Verifique sua conexão e tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    }
  }

  Future<void> _confirmDelete(SlaTemplateView template) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Modelo'),
        content: Text(
          'Deseja realmente excluir o modelo "${template.name}"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: VeraProbColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await deleteSlaTemplate(template.id, template.organizationId, ref);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Modelo removido com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível excluir o modelo. Tente novamente mais tarde.',
            ),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  const _SectionHeader({required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: VeraProbTypography.badge.copyWith(
            color: VeraProbColors.textSecondary,
            letterSpacing: 1.2,
            fontSize: 11,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 64,
              color: VeraProbColors.textDisabled.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum modelo customizado ainda.',
              style: VeraProbTypography.bodyMedium.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Clone um modelo do sistema ou crie um do zero.',
              style: VeraProbTypography.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onCreate,
              child: const Text('Criar Primeiro Modelo'),
            ),
          ],
        ),
      ),
    );
  }
}
