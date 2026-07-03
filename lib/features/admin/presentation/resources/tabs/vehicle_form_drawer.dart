import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'package:veraprob/features/shared/providers.dart';

class VehicleFormDrawer extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String> onVehicleAdded;

  const VehicleFormDrawer({
    super.key,
    required this.onClose,
    required this.onVehicleAdded,
  });

  @override
  ConsumerState<VehicleFormDrawer> createState() => _VehicleFormDrawerState();
}

class _VehicleFormDrawerState extends ConsumerState<VehicleFormDrawer>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  final _modelController = TextEditingController();
  final _capacityController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _plateController.dispose();
    _modelController.dispose();
    _capacityController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleClose() async {
    await _animController.reverse();
    widget.onClose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final vehicle = await ref
          .read(vehicleAssetRepositoryProvider)
          .addVehicle(
            plate: _plateController.text.trim(),
            model: _modelController.text.trim().isNotEmpty
                ? _modelController.text.trim()
                : null,
            capacity: int.parse(_capacityController.text.trim()),
          );
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              // ACCENT-FILL-CONTRAST: dark foreground on accent fill.
              Icon(
                Icons.check_circle,
                color: VeraProbColors.background,
                size: 20,
              ),
              SizedBox(width: 10),
              Text(
                'Veículo cadastrado com sucesso',
                style: TextStyle(color: VeraProbColors.background),
              ),
            ],
          ),
          backgroundColor: VeraProbColors.success,
          duration: Duration(seconds: 3),
        ),
      );
      widget.onVehicleAdded(vehicle.id);
    } catch (e, stack) {
      LoggerService().error(
        'Falha ao cadastrar veículo',
        error: e,
        stackTrace: stack,
      );
      String? msg;
      final errStr = e.toString();
      if (errStr.contains('P0001')) {
        // PostgrestException with code P0001 carries a business-logic message
        msg = errStr.replaceFirst(RegExp(r'^.*?: '), '').trim();
        if (msg.isEmpty) msg = null;
      } else if (errStr.contains('uq_vehicles_org_plate')) {
        msg = 'Esta placa já está cadastrada na frota.';
      } else {
        msg = 'Não foi possível salvar o veículo agora. Tente novamente.';
      }
      setState(() {
        _errorMessage = msg;
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        elevation: 8,
        child: Container(
          width: 420,
          color: VeraProbColors.surface,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: VeraProbColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: VeraProbRadii.mdAll,
                      ),
                      child: Icon(
                        Icons.directions_bus,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Cadastrar veículo',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _handleClose,
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _fieldLabel('Placa'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _plateController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: ABC-1234',
                          ),
                          textCapitalization: TextCapitalization.characters,
                          enabled: !_isSaving,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'A placa é obrigatória';
                            }
                            final plate = v.trim().toUpperCase();
                            final br = RegExp(r'^[A-Z]{3}-[0-9]{4}$');
                            final mercosul = RegExp(
                              r'^[A-Z]{3}[0-9][A-Z][0-9]{2}$',
                            );
                            if (!br.hasMatch(plate) &&
                                !mercosul.hasMatch(plate)) {
                              return 'Use ABC-1234 (BR) ou ABC1D23 (Mercosul)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Modelo (opcional)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _modelController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: Mercedes-Benz O500',
                          ),
                          textCapitalization: TextCapitalization.words,
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Capacidade (passageiros)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _capacityController,
                          decoration: const InputDecoration(hintText: 'Ex: 48'),
                          keyboardType: TextInputType.number,
                          enabled: !_isSaving,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'A capacidade é obrigatória';
                            }
                            final n = int.tryParse(v.trim());
                            if (n == null || n < 0) {
                              return 'Informe um número válido';
                            }
                            return null;
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: VeraProbColors.error.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: VeraProbRadii.mdAll,
                              border: Border.all(
                                color: VeraProbColors.error.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber,
                                  size: 18,
                                  color: VeraProbColors.error,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: VeraProbColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: VeraProbColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : _handleClose,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _handleSubmit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  // ACCENT-FILL-CONTRAST: dark fg on fill.
                                  color: VeraProbColors.background,
                                ),
                              )
                            : const Text(
                                'Cadastrar',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                      ),
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

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: VeraProbColors.textPrimary,
      ),
    );
  }
}
