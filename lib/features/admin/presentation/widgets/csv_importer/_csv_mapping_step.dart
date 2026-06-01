import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore
import 'package:veraprob/features/admin/presentation/utils/csv_target_field_labels.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_theme.dart';
import 'package:veraprob/features/admin/providers/csv_import_providers.dart';

/// Step 1 — map CSV headers → CsvTargetField + preview rows + save-as-template.
class CsvMappingStep extends ConsumerStatefulWidget {
  const CsvMappingStep({super.key});

  @override
  ConsumerState<CsvMappingStep> createState() => _CsvMappingStepState();
}

class _CsvMappingStepState extends ConsumerState<CsvMappingStep> {
  late final TextEditingController _templateNameController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(csvImportFlowProvider);
    final name = state is CsvImportMapped ? state.templateName : '';
    _templateNameController = TextEditingController(text: name);
  }

  @override
  void dispose() {
    _templateNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawState = ref.watch(csvImportFlowProvider);
    final state = rawState.activeState;
    if (state is! CsvImportMapped) return const SizedBox.shrink();

    final notifier = ref.read(csvImportFlowProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TemplatePicker(targetEntity: state.targetEntity),
          const SizedBox(height: 20),
          Text(
            'Mapeamento de colunas',
            style: CsvT.labelStyle(color: CsvT.textHi, size: 14),
          ),
          Text(
            '${state.headers.length} coluna(s) detectada(s) em "${state.fileName}"',
            style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
          ),
          const SizedBox(height: 12),
          ...state.headers.map((header) {
            final mapping = state.mappings[header];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MappingRow(
                csvHeader: header,
                currentField: mapping?.targetField,
                currentTransform: mapping?.transform,
                targetEntity: state.targetEntity,
                previewValue: state.previewRows.isNotEmpty
                    ? (state.previewRows.first[header] ?? '')
                    : '',
                onFieldChanged: (field) =>
                    notifier.updateMapping(header, field, mapping?.transform),
                onTransformChanged: (t) =>
                    notifier.updateMapping(header, mapping?.targetField, t),
              ),
            );
          }),
          const SizedBox(height: 16),
          _PreviewTable(headers: state.headers, previewRows: state.previewRows),
          const SizedBox(height: 16),
          _SaveTemplateSection(
            saveAsTemplate: state.saveAsTemplate,
            templateName: state.templateName,
            controller: _templateNameController,
            onToggle: notifier.toggleSaveTemplate,
            onNameChanged: notifier.setTemplateName,
          ),
        ],
      ),
    );
  }
}

// ── Template Picker ────────────────────────────────────────────────────────────

class _TemplatePicker extends ConsumerWidget {
  const _TemplatePicker({required this.targetEntity});

  final String targetEntity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(csvTemplatesProvider(targetEntity));
    final rawState = ref.watch(csvImportFlowProvider);
    final state = rawState.activeState;
    final notifier = ref.read(csvImportFlowProvider.notifier);
    final selectedId = state is CsvImportMapped
        ? state.selectedTemplateId
        : null;

    return templatesAsync.when(
      loading: () => const SizedBox(
        height: 36,
        child: LinearProgressIndicator(color: CsvT.action),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (templates) {
        if (templates.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usar template salvo',
              style: CsvT.labelStyle(color: CsvT.textLo),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedId,
              hint: Text(
                'Selecionar template…',
                style: CsvT.labelStyle(color: CsvT.textLo),
              ),
              dropdownColor: CsvT.bgCard,
              style: CsvT.labelStyle(),
              decoration: InputDecoration(
                filled: true,
                fillColor: CsvT.bgSlate,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CsvT.radiusChip),
                  borderSide: const BorderSide(color: CsvT.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CsvT.radiusChip),
                  borderSide: const BorderSide(color: CsvT.border),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: templates.map((t) {
                return DropdownMenuItem(value: t.id, child: Text(t.name));
              }).toList(),
              onChanged: (id) {
                if (id == null) return;
                final template = templates.firstWhere((t) => t.id == id);
                notifier.applyTemplate(template);
              },
            ),
          ],
        );
      },
    );
  }
}

// ── Mapping Row ────────────────────────────────────────────────────────────────

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.csvHeader,
    required this.currentField,
    required this.currentTransform,
    required this.targetEntity,
    required this.previewValue,
    required this.onFieldChanged,
    required this.onTransformChanged,
  });

  final String csvHeader;
  final CsvTargetField? currentField;
  final String? currentTransform;
  final String targetEntity;
  final String previewValue;
  final ValueChanged<CsvTargetField?> onFieldChanged;
  final ValueChanged<String?> onTransformChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: CsvT.cardDecoration(radius: CsvT.radiusChip),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 480;
          final content = [
            // CSV header label + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    csvHeader,
                    style: CsvT.labelStyle(color: CsvT.textHi),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (previewValue.isNotEmpty)
                    Text(
                      previewValue,
                      style: CsvT.labelStyle(color: CsvT.textLo, size: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            SizedBox(width: narrow ? 0 : 8),
            // Target field dropdown
            SizedBox(
              width: narrow ? double.infinity : 220,
              child: _TargetFieldDropdown(
                value: currentField,
                targetEntity: targetEntity,
                onChanged: onFieldChanged,
              ),
            ),
            if (currentField != null) ...[
              const SizedBox(width: 8),
              _TransformChip(
                value: currentTransform,
                onChanged: onTransformChanged,
              ),
            ],
          ];

          return narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content,
                )
              : Row(children: content);
        },
      ),
    );
  }
}

// ── Target Field Dropdown ─────────────────────────────────────────────────────

class _TargetFieldDropdown extends StatelessWidget {
  const _TargetFieldDropdown({
    required this.value,
    required this.targetEntity,
    required this.onChanged,
  });

  final CsvTargetField? value;
  final String targetEntity;
  final ValueChanged<CsvTargetField?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<CsvTargetField>(
      initialValue: value,
      hint: Text(
        'Ignorar coluna',
        style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
      ),
      isExpanded: true,
      dropdownColor: CsvT.bgCard,
      style: CsvT.labelStyle(size: 12),
      decoration: InputDecoration(
        filled: true,
        fillColor: CsvT.bgSlate,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CsvT.radiusChip),
          borderSide: const BorderSide(color: CsvT.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CsvT.radiusChip),
          borderSide: const BorderSide(color: CsvT.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        DropdownMenuItem<CsvTargetField>(
          value: null,
          child: Text(
            'Ignorar coluna',
            style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
          ),
        ),
        // Bloco 1A: filter by entity scope — never show Latitude for Contractor, etc.
        ...CsvTargetField.forEntity(targetEntity).map((f) {
          return DropdownMenuItem(
            value: f,
            child: Text(
              csvTargetFieldLabel(f),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
      onChanged: onChanged,
    );
  }
}

// ── Transform Chip ─────────────────────────────────────────────────────────────

const _kTransforms = {
  'uppercase': 'MAIÚSC',
  'lowercase': 'minúsc',
  'trim': 'Trim',
  'cnpj_strip': 'CNPJ',
  'date_iso': 'ISO Date',
};

class _TransformChip extends StatelessWidget {
  const _TransformChip({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      tooltip: 'Transformação',
      color: CsvT.bgCard,
      itemBuilder: (_) => [
        PopupMenuItem<String?>(
          value: null,
          child: Text('Nenhuma', style: CsvT.labelStyle(color: CsvT.textLo)),
        ),
        ..._kTransforms.entries.map(
          (e) => PopupMenuItem<String?>(
            value: e.key,
            child: Text(e.value, style: CsvT.labelStyle()),
          ),
        ),
      ],
      onSelected: onChanged,
      child: Chip(
        label: Text(
          value != null ? (_kTransforms[value] ?? value!) : 'T',
          style: CsvT.labelStyle(
            color: value != null ? CsvT.action : CsvT.textLo,
            size: 11,
          ),
        ),
        backgroundColor: CsvT.bgSlate,
        side: BorderSide(color: value != null ? CsvT.action : CsvT.border),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ── Preview Table ─────────────────────────────────────────────────────────────

class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.headers, required this.previewRows});

  final List<String> headers;
  final List<Map<String, String>> previewRows;

  @override
  Widget build(BuildContext context) {
    if (previewRows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pré-visualização (${previewRows.length} linha(s))',
          style: CsvT.labelStyle(color: CsvT.textLo, size: 12),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: CsvT.cardDecoration(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(CsvT.bgSlate),
              dataRowColor: WidgetStateProperty.all(CsvT.bgCard),
              headingTextStyle: CsvT.labelStyle(color: CsvT.textLo, size: 12),
              dataTextStyle: CsvT.labelStyle(color: CsvT.textHi, size: 12),
              columnSpacing: 16,
              horizontalMargin: 12,
              columns: headers
                  .map(
                    (h) => DataColumn(
                      label: Text(h, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              rows: previewRows.map((row) {
                return DataRow(
                  cells: headers
                      .map(
                        (h) => DataCell(
                          Text(row[h] ?? '', overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Save Template Section ─────────────────────────────────────────────────────

class _SaveTemplateSection extends StatelessWidget {
  const _SaveTemplateSection({
    required this.saveAsTemplate,
    required this.templateName,
    required this.controller,
    required this.onToggle,
    required this.onNameChanged,
  });

  final bool saveAsTemplate;
  final String templateName;
  final TextEditingController controller;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onNameChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: saveAsTemplate,
              onChanged: (v) => onToggle(v ?? false),
              activeColor: CsvT.action,
              side: const BorderSide(color: CsvT.textLo),
            ),
            Text(
              'Salvar como template para reutilização',
              style: CsvT.labelStyle(color: CsvT.textHi),
            ),
          ],
        ),
        if (saveAsTemplate) ...[
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            style: CsvT.labelStyle(),
            decoration: InputDecoration(
              hintText: 'Nome do template…',
              hintStyle: CsvT.labelStyle(color: CsvT.textLo),
              filled: true,
              fillColor: CsvT.bgSlate,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CsvT.radiusChip),
                borderSide: const BorderSide(color: CsvT.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CsvT.radiusChip),
                borderSide: const BorderSide(color: CsvT.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CsvT.radiusChip),
                borderSide: const BorderSide(color: CsvT.action),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: onNameChanged,
          ),
        ],
      ],
    );
  }
}
