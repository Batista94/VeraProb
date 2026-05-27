import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_theme.dart';
import 'package:veraprob/features/admin/providers/csv_import_providers.dart';

/// Step 0 — file picker + entity selector + template picker.
class CsvUploadStep extends ConsumerWidget {
  const CsvUploadStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(csvImportFlowProvider);
    final notifier = ref.read(csvImportFlowProvider.notifier);

    final targetEntity = state is CsvImportInitial
        ? state.targetEntity
        : 'operator';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EntitySelector(current: targetEntity, onChanged: notifier.setEntity),
          const SizedBox(height: 20),
          _DropZone(notifier: notifier),
          const SizedBox(height: 12),
          Text(
            'Formatos suportados: .csv, .tsv · Codificação UTF-8',
            style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
          ),
        ],
      ),
    );
  }
}

// ── Entity Selector ────────────────────────────────────────────────────────────

const _kEntityLabels = {
  'operator': 'Operadores / Motoristas',
  'contract': 'Contratos / Contratantes',
  'zone': 'Zonas Operacionais',
  'asset': 'Ativos (Veículos)',
};

class _EntitySelector extends StatelessWidget {
  const _EntitySelector({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tipo de entidade', style: CsvT.labelStyle(color: CsvT.textLo)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kEntityLabels.entries.map((e) {
            final isSelected = e.key == current;
            return ChoiceChip(
              label: Text(e.value),
              selected: isSelected,
              onSelected: (_) => onChanged(e.key),
              backgroundColor: CsvT.bgSlate,
              selectedColor: CsvT.action.withValues(alpha: 0.18),
              labelStyle: CsvT.labelStyle(
                color: isSelected ? CsvT.action : CsvT.textLo,
              ),
              side: BorderSide(color: isSelected ? CsvT.action : CsvT.border),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Drop Zone ─────────────────────────────────────────────────────────────────

class _DropZone extends StatelessWidget {
  const _DropZone({required this.notifier});

  final CsvImportFlowNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: notifier.pickFile,
      borderRadius: BorderRadius.circular(CsvT.radiusCard),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
          color: CsvT.bgSlate,
          borderRadius: BorderRadius.circular(CsvT.radiusCard),
          border: Border.all(
            color: CsvT.action.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.upload_file_outlined,
              color: CsvT.action,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Clique para selecionar arquivo CSV',
              style: CsvT.labelStyle(color: CsvT.textHi, size: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'ou arraste e solte aqui',
              style: CsvT.labelStyle(color: CsvT.textLo, size: 13),
            ),
          ],
        ),
      ),
    );
  }
}
