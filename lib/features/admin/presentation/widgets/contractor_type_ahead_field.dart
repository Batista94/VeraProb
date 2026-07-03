import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/sla_audit/projections/contractor_view.dart';

import 'contractor_form_dialog.dart';

// ── Filter helper ─────────────────────────────────────────────

List<ContractorView> filterContractors(
  List<ContractorView> contractors,
  String query,
) {
  if (query.isEmpty) {
    return contractors;
  }

  final lower = query.toLowerCase();
  return contractors
      .where(
        (c) =>
            c.name.toLowerCase().contains(lower) ||
            (c.taxId?.toLowerCase().contains(lower) ?? false),
      )
      .toList();
}

// ── Widget ────────────────────────────────────────────────────

/// A type-ahead (autocomplete) field for selecting or Just-in-Time creating a
/// [Contractor].
class ContractorTypeAheadField extends StatefulWidget {
  final String label;
  final IconData prefixIcon;

  /// Full list of contractors available for the organization.
  final List<ContractorView> contractors;

  /// The currently selected contractor.
  final ContractorView? selectedContractor;

  /// Invalidates the contractors cache after the modal creates/edits a contractor.
  final Future<void> Function() onInvalidateContractors;

  /// Called when the user selects an existing contractor or after contractor creation.
  final ValueChanged<ContractorView?> onChanged;

  const ContractorTypeAheadField({
    super.key,
    required this.label,
    required this.prefixIcon,
    required this.contractors,
    required this.selectedContractor,
    required this.onInvalidateContractors,
    required this.onChanged,
  });

  @override
  State<ContractorTypeAheadField> createState() =>
      _ContractorTypeAheadFieldState();
}

class _ContractorTypeAheadFieldState extends State<ContractorTypeAheadField> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _fieldFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textController.text = widget.selectedContractor?.name ?? '';
    _textController.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant ContractorTypeAheadField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedContractor != oldWidget.selectedContractor) {
      _textController.text = widget.selectedContractor?.name ?? '';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _fieldFocusNode.dispose();
    super.dispose();
  }

  // ── Modal creation ────────────────────────────────────────────

  Future<void> _triggerCreationDialog() async {
    final initialName = _textController.text.trim();
    final contractor = await showContractorFormDialog(
      context,
      initialName: initialName.isNotEmpty ? initialName : null,
    );
    if (!mounted || contractor == null) return;

    // Auto-select the newly created contractor!
    _textController.text = contractor.name;
    widget.onChanged(contractor);
    await widget.onInvalidateContractors();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_buildAutocomplete(), _buildCreateButton()],
    );
  }

  /// Shows "+ Criar contractor 'X'" below the field when no exact name match exists.
  Widget _buildCreateButton() {
    final query = _textController.text.trim();
    final hasExactMatch = widget.contractors.any(
      (c) => c.name.toLowerCase() == query.toLowerCase(),
    );
    if (hasExactMatch) return const SizedBox.shrink();

    final label = query.isEmpty
        ? '+ Criar novo contratante'
        : '+ Criar contratante "$query"';

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.add_business, size: 14),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: VeraProbColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: _triggerCreationDialog,
      ),
    );
  }

  Widget _buildAutocomplete() {
    return Autocomplete<ContractorView>(
      initialValue: TextEditingValue(
        text: widget.selectedContractor?.name ?? '',
      ),
      optionsBuilder: (textEditingValue) {
        return filterContractors(widget.contractors, textEditingValue.text);
      },
      displayStringForOption: (contractor) => contractor.name,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        final selectedContractor = widget.selectedContractor;

        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          style: VeraProbTypography.bodyMedium,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(widget.prefixIcon),
            suffixIcon: selectedContractor != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      widget.onChanged(null);
                      controller.clear();
                      focusNode.unfocus();
                    },
                  )
                : null,
          ),
          onChanged: (v) => _textController.text = v,
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final optionList = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: VeraProbRadii.mdAll,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 280,
                maxWidth: (MediaQuery.sizeOf(context).width * 0.9).clamp(
                  240.0,
                  480.0,
                ),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: optionList.length,
                itemBuilder: (context, index) {
                  final contractor = optionList[index];

                  return ListTile(
                    leading: const Icon(
                      Icons.business,
                      size: 18,
                      color: VeraProbColors.primary,
                    ),
                    title: Text(contractor.name),
                    subtitle: contractor.taxId != null
                        ? Text(contractor.taxId!)
                        : null,
                    onTap: () => onSelected(contractor),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (contractor) {
        _textController.text = contractor.name;
        widget.onChanged(contractor);
      },
    );
  }
}
