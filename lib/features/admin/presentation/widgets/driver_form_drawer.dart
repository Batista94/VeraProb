import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/shared/providers.dart';

class DriverFormDrawer extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String> onDriverAdded;

  const DriverFormDrawer({
    super.key,
    required this.onClose,
    required this.onDriverAdded,
  });

  @override
  ConsumerState<DriverFormDrawer> createState() => _DriverFormDrawerState();
}

class _DriverFormDrawerState extends ConsumerState<DriverFormDrawer>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cnhController = TextEditingController();
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
    _nameController.dispose();
    _cnhController.dispose();
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

    try {
      final newDriver = Driver(
        id: DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
        organizationId: '', // injected by repository from JWT on INSERT
        name: _nameController.text.trim(),
        licenseNumber: _cnhController.text.trim(),
      );

      await ref.read(driverRepositoryProvider).addDriver(newDriver);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Motorista cadastrado com sucesso'),
              ],
            ),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 3),
          ),
        );
        widget.onDriverAdded(newDriver.id);
      }
    } catch (e, stack) {
      if (e.toString().contains('DUPLICATE_CNH')) {
        setState(() {
          _errorMessage = 'Este motorista já está cadastrado na frota.';
          _isSaving = false;
        });
      } else {
        LoggerService().error(
          'Falha ao cadastrar motorista',
          error: e,
          stackTrace: stack,
        );
        setState(() {
          _errorMessage =
              'Não foi possível salvar o motorista agora. Tente novamente.';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        elevation: 8,
        color: VeraProbColors.surface,
        child: Container(
          width: 420,
          color: VeraProbColors.surface,
          child: Column(
            children: [
              // Drawer header
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
                        color: VeraProbColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1,
                        size: 22,
                        color: VeraProbColors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Cadastrar motorista',
                        style: VeraProbTypography.sectionTitle,
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
              // Form body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Info banner
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: VeraProbColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: VeraProbColors.primary.withValues(
                                alpha: 0.3,
                              ),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 18,
                                color: VeraProbColors.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Este cadastro registra o motorista na frota. O acesso ao sistema é configurado separadamente.',
                                  style: VeraProbTypography.bodyMedium.copyWith(
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Name field
                        Text(
                          'Nome completo',
                          style: VeraProbTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: João Carlos da Silva',
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'O nome é obrigatório';
                            }
                            if (v.trim().length < 3) {
                              return 'Informe o nome completo';
                            }
                            return null;
                          },
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 24),

                        // CNH field
                        Text(
                          'Número da CNH',
                          style: VeraProbTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _cnhController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: 12345678900',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'O número da CNH é obrigatório';
                            }
                            if (v.trim().length < 9) {
                              return 'CNH deve ter no mínimo 9 dígitos';
                            }
                            return null;
                          },
                          enabled: !_isSaving,
                        ),

                        // Error message
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: VeraProbColors.error.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(8),
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
                                    style: VeraProbTypography.bodyMedium
                                        .copyWith(color: VeraProbColors.error),
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
              // Drawer footer
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
                                  valueColor: AlwaysStoppedAnimation(
                                    VeraProbColors.background,
                                  ),
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
}
