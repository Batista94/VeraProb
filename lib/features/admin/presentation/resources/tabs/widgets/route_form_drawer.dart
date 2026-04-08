import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/services/logger_service.dart';
import 'package:veraprob/application/admin/route_command_service_provider.dart';

/// Form drawer for creating a new route.
///
/// Uses [RouteCommandService] instead of directly accessing the repository.
class RouteFormDrawer extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<String> onRouteAdded;

  const RouteFormDrawer({
    super.key,
    required this.onClose,
    required this.onRouteAdded,
  });

  @override
  ConsumerState<RouteFormDrawer> createState() => _RouteFormDrawerState();
}

class _RouteFormDrawerState extends ConsumerState<RouteFormDrawer>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _shortNameController = TextEditingController();
  final _longNameController = TextEditingController();
  final _colorController = TextEditingController();
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
    _shortNameController.dispose();
    _longNameController.dispose();
    _colorController.dispose();
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
      final route = await ref
          .read(routeCommandServiceProvider)
          .addRoute(
            shortName: _shortNameController.text.trim(),
            longName: _longNameController.text.trim(),
            color: _colorController.text.trim().isNotEmpty
                ? _colorController.text.trim()
                : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Rota cadastrada com sucesso'),
              ],
            ),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 3),
          ),
        );
        widget.onRouteAdded(route.id);
      }
    } catch (e, stack) {
      LoggerService().error(
        'Falha ao cadastrar rota',
        error: e,
        stackTrace: stack,
      );
      setState(() {
        _errorMessage =
            'Não foi possível salvar a rota agora. Tente novamente.';
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
          color: Colors.white,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.route,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Cadastrar rota',
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
                        _fieldLabel('Nome curto'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _shortNameController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: L001',
                          ),
                          textCapitalization: TextCapitalization.characters,
                          enabled: !_isSaving,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'O nome curto é obrigatório';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Nome completo'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _longNameController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: Terminal Central → Zona Norte',
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          enabled: !_isSaving,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'O nome completo é obrigatório';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Cor (hex, opcional)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _colorController,
                          decoration: const InputDecoration(
                            hintText: 'Ex: #3F51B5',
                          ),
                          enabled: !_isSaving,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  size: 18,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.red.shade800,
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
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
                                  color: Colors.white,
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
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade800,
      ),
    );
  }
}
