import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart'; // pr_scanner: ignore
import 'package:veraprob/state/providers/dispute_reason_code_providers.dart';

/// Componente 4.1 — Structured reason-code selector for dispute resolution.
///
/// A [DropdownMenu] **grouped by `category`** (non-selectable section headers
/// before each block of codes) rather than a flat list, so an auditor scans the
/// taxonomy by intent (Operacional / Técnico / …). Surfaces the catalogue from
/// [disputeReasonCodesProvider]:
/// - loading → skeleton (WASM cold start ~600ms),
/// - error / empty → domain-language message (Lesson 5),
/// - data → grouped, single-select.
///
/// Emits the selected `code` (the agnostic taxonomy key, B6) via [onChanged];
/// the caller threads it into `ResolveDisputeCommand.reasonCode`.
class DisputeReasonCodeDropdown extends ConsumerWidget {
  final String? selectedCode;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String label;

  const DisputeReasonCodeDropdown({
    super.key,
    required this.selectedCode,
    required this.onChanged,
    this.enabled = true,
    this.label = 'Motivo (taxonomia)',
  });

  /// Display order + PT header for each catalogue category.
  static const _categoryOrder = <String, String>{
    'OPERATIONAL': 'Operacional',
    'TECHNICAL': 'Técnico',
    'CONTRACTUAL': 'Contratual',
    'ENVIRONMENTAL': 'Ambiental',
    'REGULATORY': 'Regulatório',
    'OTHER': 'Outros',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codesAsync = ref.watch(disputeReasonCodesProvider);

    return switch (codesAsync) {
      AsyncLoading() => const _DropdownSkeleton(),
      AsyncError() => const _DropdownMessage(
        icon: Icons.error_outline,
        message: 'Não foi possível carregar os motivos. Tente novamente.',
        color: VeraProbColors.error,
      ),
      AsyncData(:final value) =>
        value.isEmpty
            ? const _DropdownMessage(
                icon: Icons.inbox_outlined,
                message: 'Nenhum motivo disponível no catálogo.',
                color: VeraProbColors.textDisabled,
              )
            : _buildMenu(value),
    };
  }

  Widget _buildMenu(List<DisputeReasonCode> codes) {
    final entries = <DropdownMenuEntry<String>>[];

    for (final entry in _categoryOrder.entries) {
      final inCategory = codes.where((c) => c.category == entry.key).toList()
        ..sort((a, b) => a.labelPt.compareTo(b.labelPt));
      if (inCategory.isEmpty) continue;

      // Non-selectable section header.
      entries.add(
        DropdownMenuEntry<String>(
          value: '__header_${entry.key}',
          enabled: false,
          label: entry.value.toUpperCase(),
          style: MenuItemButton.styleFrom(
            foregroundColor: VeraProbColors.textDisabled,
            textStyle: VeraProbTypography.badge.copyWith(
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
      for (final c in inCategory) {
        entries.add(DropdownMenuEntry<String>(value: c.code, label: c.labelPt));
      }
    }

    return DropdownMenu<String>(
      key: const ValueKey('dispute-reason-code-dropdown'),
      initialSelection: selectedCode,
      enabled: enabled,
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      label: Text(label),
      leadingIcon: const Icon(Icons.category_outlined, size: 18),
      dropdownMenuEntries: entries,
      onSelected: onChanged,
      textStyle: const TextStyle(fontSize: 13),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _DropdownSkeleton extends StatelessWidget {
  const _DropdownSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Carregando motivos…',
            style: TextStyle(fontSize: 12, color: VeraProbColors.textDisabled),
          ),
        ],
      ),
    );
  }
}

class _DropdownMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _DropdownMessage({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(message, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}
