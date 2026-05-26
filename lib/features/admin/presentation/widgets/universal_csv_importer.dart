import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore

/// Industrial Deep Universal CSV Importer Dialog
/// Follows UX Standards (INV-25): No pure white, glassmorphism, 1px borders.
class UniversalCsvImporterDialog extends ConsumerStatefulWidget {
  const UniversalCsvImporterDialog({super.key});

  @override
  ConsumerState<UniversalCsvImporterDialog> createState() =>
      _UniversalCsvImporterDialogState();
}

class _UniversalCsvImporterDialogState
    extends ConsumerState<UniversalCsvImporterDialog> {
  int _currentStep = 0;

  // State for Step 1
  String _selectedEntity = 'asset';
  String _selectedTemplate = 'new';
  bool _isFileUploaded = false;

  // State for Step 2
  final List<String> _csvHeaders = [
    'PLACA',
    'MODELO',
    'QTD_LUGARES',
    'OBS_INTERNA',
  ]; // Mock headers
  final Map<String, CsvTargetField?> _mappings = {};

  @override
  void initState() {
    super.initState();
    // Pre-populate mock state
    _mappings['PLACA'] = CsvTargetField.identifier;
    _mappings['MODELO'] = CsvTargetField.assetModel;
    _mappings['QTD_LUGARES'] = CsvTargetField.capacity;
    _mappings['OBS_INTERNA'] = null;
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A0A0A), // Deep Dark
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(
          color: Color.fromRGBO(255, 255, 255, 0.06),
          width: 1,
        ),
      ),
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'IMPORTADOR UNIVERSAL DE DADOS',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE5E5E5),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stepper Header
            _buildStepperHeader(),
            const SizedBox(height: 32),

            // Stepper Content
            Expanded(
              child: IndexedStack(
                index: _currentStep,
                children: [
                  _buildUploadStep(),
                  _buildMappingStep(),
                  _buildValidationStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStepIndicator(0, '① UPLOAD'),
        _buildStepDivider(),
        _buildStepIndicator(1, '② MAPEAMENTO'),
        _buildStepDivider(),
        _buildStepIndicator(2, '③ VALIDAÇÃO'),
      ],
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentStep >= step;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF00A3FF).withValues(alpha: 0.1)
            : const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00A3FF).withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive
              ? const Color(0xFF00A3FF).withValues(alpha: 0.1)
              : const Color(0xFF1A1A2E),
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildStepDivider() {
    return Expanded(
      child: Container(
        height: 1,
        color: const Color.fromRGBO(255, 255, 255, 0.1),
        margin: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  Widget _buildUploadStep() {
    return Column(
      children: [
        // Dropzone
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isFileUploaded
                    ? const Color(0xFF34C759)
                    : const Color.fromRGBO(255, 255, 255, 0.1),
                style: BorderStyle.solid,
                width: 1,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isFileUploaded
                        ? Icons.check_circle_outline
                        : Icons.cloud_upload_outlined,
                    size: 64,
                    color: _isFileUploaded
                        ? const Color(0xFF34C759)
                        : const Color(0xFF00A3FF),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isFileUploaded
                        ? 'frota_norte_2026.csv (14.2 KB)'
                        : 'Arraste o arquivo CSV aqui\nou clique para selecionar',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFE5E5E5),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_isFileUploaded)
                    const Text(
                      'Formatos: .csv, .tsv | Máx: 10MB',
                      style: TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
                    ),
                  const SizedBox(height: 24),
                  if (!_isFileUploaded)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00A3FF),
                      ),
                      onPressed: () {
                        setState(() => _isFileUploaded = true);
                      },
                      child: const Text('SELECIONAR ARQUIVO'),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Selectors
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Tipo de Entidade',
                value: _selectedEntity,
                items: const [
                  DropdownMenuItem(
                    value: 'asset',
                    child: Text('Ativo (Veículo)'),
                  ),
                  DropdownMenuItem(value: 'contract', child: Text('Contrato')),
                  DropdownMenuItem(
                    value: 'operator',
                    child: Text('Operador (Motorista)'),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedEntity = v!),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Template Salvo',
                value: _selectedTemplate,
                items: const [
                  DropdownMenuItem(
                    value: 'new',
                    child: Text('Nenhum — Novo Mapeamento'),
                  ),
                  DropdownMenuItem(
                    value: 'tpl_1',
                    child: Text('Padrão ERP Sênior'),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedTemplate = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _isFileUploaded ? _nextStep : null,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('MAPEAMENTO'),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1A2E),
              style: const TextStyle(color: Colors.white),
              value: value,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMappingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'MAPEAMENTO DE COLUNAS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.06),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMappingHeaderRow(),
                const Divider(color: Colors.white12),
                ..._csvHeaders.map(_buildMappingRow),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Checkbox(
                  value: true,
                  onChanged: (v) {},
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? const Color(0xFF00A3FF)
                        : Colors.transparent,
                  ),
                ),
                const Text(
                  'Salvar como Template',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _prevStep,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('VOLTAR'),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00A3FF),
                  ),
                  onPressed: _nextStep,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('VALIDAR'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMappingHeaderRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'COLUNA DO CSV',
              style: TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'CAMPO VERAPROB',
              style: TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'TRANSFORM',
              style: TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMappingRow(String csvHeader) {
    final target = _mappings[csvHeader];
    final isMapped = target != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  isMapped ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: isMapped
                      ? const Color(0xFF34C759)
                      : const Color(0xFFFFCC00),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  csvHeader,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<CsvTargetField?>(
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1A2E),
                  style: const TextStyle(color: Colors.white),
                  value: target,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text(
                        '(Ignorar)',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                    ...CsvTargetField.values.map(
                      (f) => DropdownMenuItem(value: f, child: Text(f.name)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _mappings[csvHeader] = v),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: Text(
              isMapped ? 'UPPERCASE' : '—',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bar_chart, color: Color(0xFF00A3FF)),
                  SizedBox(width: 12),
                  Text(
                    '150 linhas analisadas',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF34C759), size: 16),
                  SizedBox(width: 8),
                  Text('142 válidas', style: TextStyle(color: Colors.white)),
                  SizedBox(width: 24),
                  Icon(Icons.cancel, color: Color(0xFFFF3B30), size: 16),
                  SizedBox(width: 8),
                  Text('8 com erros', style: TextStyle(color: Colors.white)),
                ],
              ),
              const SizedBox(height: 24),
              // Progress Bar
              Container(
                height: 8,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 142,
                      child: Container(color: const Color(0xFF34C759)),
                    ),
                    Expanded(
                      flex: 8,
                      child: Container(color: const Color(0xFFFF3B30)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Error Details Title
        const Text(
          'Erros Detalhados (Delta)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // Error List
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              children: [
                _buildErrorRow(
                  12,
                  'Identificador',
                  'Valor obrigatório não preenchido',
                ),
                _buildErrorRow(34, 'CNPJ', 'Dígito verificador inválido'),
                _buildErrorRow(34, 'CNPJ', 'Duplicado na linha 12'),
                _buildErrorRow(
                  67,
                  'Data Início',
                  'Formato inválido (use DD/MM/AAAA)',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Warning
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFCC00).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFFFCC00).withValues(alpha: 0.5),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFFCC00)),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  '8 linhas com erro serão IGNORADAS. Apenas as 142 linhas válidas serão importadas. Deseja continuar?',
                  style: TextStyle(color: Color(0xFFFFCC00), fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () {},
              icon: const Icon(Icons.download),
              label: const Text('EXPORTAR ERROS (CSV)'),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _prevStep,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('CORRIGIR'),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF34C759),
                  ),
                  onPressed: () =>
                      Navigator.of(context).pop(), // Simulate import
                  icon: const Icon(Icons.upload),
                  label: const Text('IMPORTAR 142 LINHAS'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorRow(int line, String field, String error) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Ln $line',
              style: const TextStyle(
                color: Color(0xFFA0A0A0),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              field,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              error,
              style: const TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );
  }
}
