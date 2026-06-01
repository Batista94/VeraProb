import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_mapping_step.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_result_step.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_upload_step.dart';
import 'package:veraprob/features/admin/presentation/widgets/csv_importer/_csv_validation_step.dart';
import 'package:veraprob/features/admin/providers/csv_import_providers.dart';

// ── Public API ─────────────────────────────────────────────────────────────────

/// Opens the CSV importer dialog pre-set to [targetEntity].
/// Returns [true] if at least one row was imported (caller should refresh list).
Future<bool> showUniversalCsvImporter(
  BuildContext context, {
  required String targetEntity,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // Lesson #4
    builder: (_) => UniversalCsvImporterDialog(initialEntity: targetEntity),
  );
  return result ?? false;
}

// ── Dialog ─────────────────────────────────────────────────────────────────────

class UniversalCsvImporterDialog extends ConsumerStatefulWidget {
  const UniversalCsvImporterDialog({super.key, required this.initialEntity});

  final String initialEntity;

  @override
  ConsumerState<UniversalCsvImporterDialog> createState() =>
      _UniversalCsvImporterDialogState();
}

class _UniversalCsvImporterDialogState
    extends ConsumerState<UniversalCsvImporterDialog> {
  @override
  void initState() {
    super.initState();
    // init after first frame so provider is registered
    Future.microtask(() {
      if (mounted) {
        ref.read(csvImportFlowProvider.notifier).init(widget.initialEntity);
      }
    });
  }

  Future<void> _onCloseRequested() async {
    final state = ref.read(csvImportFlowProvider);
    final isDirty = state is CsvImportMapped || state is CsvImportValidated;
    if (isDirty && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: CsvT.bgCard,
          title: Text(
            'Cancelar importação?',
            style: CsvT.labelStyle(color: CsvT.textHi, size: 15),
          ),
          content: Text(
            'O progresso não salvo será perdido.',
            style: CsvT.labelStyle(color: CsvT.textLo),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Continuar',
                style: CsvT.labelStyle(color: CsvT.action),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Cancelar',
                style: CsvT.labelStyle(color: CsvT.error),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  void _onImportSuccess() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final rawState = ref.watch(csvImportFlowProvider);
    final state = rawState.activeState;

    return Dialog(
      backgroundColor: CsvT.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsvT.radiusCard),
        side: const BorderSide(color: CsvT.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(
              step: rawState.currentStep,
              onClose: _onCloseRequested,
            ),
            if (rawState is CsvImportError)
              _ErrorBanner(message: rawState.message),
            Flexible(
              child: AnimatedSwitcher(
                duration: CsvT.animDuration,
                switchInCurve: CsvT.animCurve,
                switchOutCurve: CsvT.animCurve,
                child: KeyedSubtree(
                  key: ValueKey(state.currentStep),
                  child: _buildContent(state),
                ),
              ),
            ),
            _DialogFooter(state: rawState),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(CsvImportFlowState state) {
    // Order matters: more-derived types checked first (inheritance chain).
    if (state is CsvImportDone) {
      return CsvResultStep(onClose: _onImportSuccess);
    }
    if (state is CsvImportValidated) {
      return CsvValidationStep(isSubmitting: state is CsvImportSubmitting);
    }
    if (state is CsvImportMapped) {
      return const CsvMappingStep();
    }
    // CsvImportError or CsvImportInitial — show upload step.
    return const CsvUploadStep();
  }
}

// ── Dialog Header ─────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.step, required this.onClose});

  final int step;
  final VoidCallback onClose;

  static const _kStepLabels = [
    'UPLOAD',
    'MAPEAMENTO',
    'VALIDAÇÃO',
    'RESULTADO',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        color: CsvT.bgCard,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CsvT.radiusCard),
        ),
        border: Border(bottom: BorderSide(color: CsvT.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_kStepLabels.length, (i) {
                return _StepPill(
                  index: i,
                  label: _kStepLabels[i],
                  currentStep: step,
                );
              }),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: CsvT.textLo,
            onPressed: onClose,
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }
}

// ── Step Pill ─────────────────────────────────────────────────────────────────

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.index,
    required this.label,
    required this.currentStep,
  });

  final int index;
  final String label;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentStep;
    final isDone = index < currentStep;

    // Fix INV-UX: text color was identical to background (alpha 0.1 over same hue).
    // Active → white text. Done → success. Inactive → textLo.
    final textColor = isActive
        ? Colors.white
        : (isDone ? CsvT.success : CsvT.textLo);
    final bgColor = isActive
        ? CsvT.action.withValues(alpha: 0.15)
        : (isDone ? CsvT.success.withValues(alpha: 0.08) : CsvT.bgSlate);
    final borderColor = isActive
        ? CsvT.action
        : (isDone ? CsvT.success.withValues(alpha: 0.4) : CsvT.border);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone)
            const Icon(Icons.check, size: 11, color: CsvT.success)
          else
            Text(
              '${index + 1}',
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error Banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: CsvT.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: CsvT.error, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: CsvT.labelStyle(color: CsvT.error, size: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dialog Footer ─────────────────────────────────────────────────────────────

class _DialogFooter extends ConsumerWidget {
  const _DialogFooter({required this.state});

  final CsvImportFlowState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(csvImportFlowProvider.notifier);
    final activeState = state.activeState;

    // Done state: footer hidden (CsvResultStep owns its own CTA).
    if (activeState is CsvImportDone) return const SizedBox.shrink();

    final isSubmitting =
        state is CsvImportSubmitting || activeState is CsvImportSubmitting;
    final canGoBack =
        activeState is CsvImportMapped || activeState is CsvImportValidated;

    Widget? primaryBtn;
    if (activeState is CsvImportValidated &&
        activeState is! CsvImportSubmitting) {
      final report = activeState.report;
      primaryBtn = FilledButton.icon(
        onPressed: notifier.submit,
        icon: const Icon(Icons.cloud_upload_outlined, size: 16),
        label: Text('Importar ${report.validRows} linha(s)'),
        style: FilledButton.styleFrom(
          backgroundColor: CsvT.action,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CsvT.radiusChip),
          ),
        ),
      );
    } else if (activeState is CsvImportMapped &&
        activeState is! CsvImportValidated) {
      final mapped = activeState;
      final hasMapping = mapped.mappings.values.any((m) => m != null);
      primaryBtn = FilledButton.icon(
        onPressed: hasMapping ? notifier.validate : null,
        icon: const Icon(Icons.rule_outlined, size: 16),
        label: const Text('Validar'),
        style: FilledButton.styleFrom(
          backgroundColor: CsvT.action,
          foregroundColor: Colors.white,
          disabledBackgroundColor: CsvT.bgSlate,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CsvT.radiusChip),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: CsvT.bgCard,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(CsvT.radiusCard),
        ),
        border: Border(top: BorderSide(color: CsvT.border)),
      ),
      child: Row(
        children: [
          if (canGoBack)
            TextButton.icon(
              onPressed: isSubmitting ? null : notifier.goBack,
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Voltar'),
              style: TextButton.styleFrom(foregroundColor: CsvT.textLo),
            ),
          const Spacer(),
          if (isSubmitting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CsvT.action,
              ),
            )
          else
            ?primaryBtn,
        ],
      ),
    );
  }
}
