import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Seção 1 das Configurações da Organização: campos estruturais + capacidades
/// + botão de salvar.
///
/// Stateless — o parent `_OrgSettingsScreenState` é dono dos controllers, da
/// `formKey` e do handler de salvamento. O bloco de capacidades é injetado via
/// [capabilitiesChild] para que o `Form` envolva ambos (o validador da
/// justificativa de capacidades depende deste `Form`).
class GeneralSettingsSection extends StatelessWidget {
  const GeneralSettingsSection({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.timezoneController,
    required this.currencyController,
    required this.logoUrlController,
    required this.orgTypeController,
    required this.isSuperAdmin,
    required this.isSaving,
    required this.onSave,
    required this.capabilitiesChild,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController timezoneController;
  final TextEditingController currencyController;
  final TextEditingController logoUrlController;
  final TextEditingController orgTypeController;
  final bool isSuperAdmin;
  final bool isSaving;
  final VoidCallback onSave;
  final Widget capabilitiesChild;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: nameController,
            readOnly: !isSuperAdmin,
            decoration: InputDecoration(
              labelText: 'Nome da Organização',
              prefixIcon: Icon(
                isSuperAdmin ? Icons.edit_outlined : Icons.lock_outline,
                size: 20,
              ),
              helperText: isSuperAdmin
                  ? 'Atualização permitida para Super Admin.'
                  : 'Campos estruturais bloqueados por contrato. Contate o suporte para alterações.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: timezoneController,
            readOnly: !isSuperAdmin,
            decoration: InputDecoration(
              labelText: 'Fuso Horário',
              prefixIcon: Icon(
                isSuperAdmin ? Icons.access_time : Icons.lock_outline,
                size: 20,
              ),
              helperText: isSuperAdmin
                  ? 'Atualização permitida para Super Admin.'
                  : 'Campos estruturais bloqueados por contrato. Contate o suporte para alterações.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: currencyController,
            readOnly: !isSuperAdmin,
            decoration: InputDecoration(
              labelText: 'Código da Moeda',
              prefixIcon: Icon(
                isSuperAdmin
                    ? Icons.monetization_on_outlined
                    : Icons.lock_outline,
                size: 20,
              ),
              helperText: isSuperAdmin
                  ? 'Atualização permitida para Super Admin.'
                  : 'Campos estruturais bloqueados por contrato. Contate o suporte para alterações.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: logoUrlController,
            decoration: const InputDecoration(
              labelText: 'URL do Logotipo',
              helperText: 'Link para imagem SVG ou PNG da marca.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: orgTypeController,
            decoration: const InputDecoration(
              labelText: 'Tipo de Operação (cosmético)',
              prefixIcon: Icon(Icons.label_outline, size: 20),
              helperText:
                  'Rótulo visual interno da sua organização (ex: Carga, Passageiros, Logística Urbana). Esta configuração não altera as regras do sistema.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 32),
          capabilitiesChild,
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        // ACCENT-FILL-CONTRAST: dark fg on fill.
                        color: VeraProbColors.background,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Salvar Alterações'),
              onPressed: isSaving ? null : onSave,
            ),
          ),
        ],
      ),
    );
  }
}
