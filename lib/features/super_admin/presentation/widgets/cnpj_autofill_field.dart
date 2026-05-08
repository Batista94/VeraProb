import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/super_admin/cnpj_lookup_exceptions.dart';
import 'package:veraprob/infrastructure/super_admin/cnpj_infrastructure_exceptions.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

enum _CnpjLookupState {
  idle,
  loading,
  success,
  invalidCnpj,
  degraded,
  rateLimited,
}

/// Standalone CNPJ autofill field that uses the proxy-based lookup service.
///
/// Routes through `super-admin-proxy` Edge Function to bypass CORS (INV-14).
class CnpjAutofillField extends ConsumerStatefulWidget {
  final TextEditingController companyNameController;

  const CnpjAutofillField({super.key, required this.companyNameController});

  @override
  ConsumerState<CnpjAutofillField> createState() => _CnpjAutofillFieldState();
}

class _CnpjAutofillFieldState extends ConsumerState<CnpjAutofillField> {
  final _cnpjController = TextEditingController();
  Timer? _debounce;
  _CnpjLookupState _state = _CnpjLookupState.idle;
  String? _errorMessage;

  @override
  void dispose() {
    _cnpjController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onCnpjChanged(String value) {
    // Any edit resets error state immediately (zero-tap dismiss).
    if (_state != _CnpjLookupState.idle && _state != _CnpjLookupState.loading) {
      setState(() {
        _state = _CnpjLookupState.idle;
        _errorMessage = null;
      });
    }
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _fetchCnpjData(value);
    });
  }

  Future<void> _fetchCnpjData(String cnpj) async {
    if (cnpj.isEmpty) return;
    final digits = cnpj.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 14) return;

    setState(() {
      _state = _CnpjLookupState.loading;
      _errorMessage = null;
    });

    try {
      final service = ref.read(cnpjLookupServiceProvider);
      final data = await service.lookup(digits);

      if (!mounted) return;
      if (data != null &&
          data.legalName != null &&
          data.legalName!.isNotEmpty) {
        widget.companyNameController.text = data.legalName!;
        setState(() => _state = _CnpjLookupState.success);
      } else {
        setState(() => _state = _CnpjLookupState.idle);
      }
    } on InvalidCnpjException {
      if (!mounted) return;
      setState(() {
        _state = _CnpjLookupState.invalidCnpj;
        _errorMessage = 'CNPJ inválido ou não encontrado na Receita.';
      });
    } on RateLimitExceededException {
      if (!mounted) return;
      setState(() {
        _state = _CnpjLookupState.rateLimited;
        _errorMessage = 'Limite atingido. Aguarde ou preencha manualmente.';
      });
    } on DataParsingException {
      // Contract drift — log-worthy but silent for the operator.
      if (!mounted) return;
      setState(() {
        _state = _CnpjLookupState.degraded;
        _errorMessage = 'Resposta inesperada. Preencha manualmente.';
      });
    } on CnpjLookupException {
      // Covers ServiceTimeoutException + ExternalApiException.
      if (!mounted) return;
      setState(() {
        _state = _CnpjLookupState.degraded;
        _errorMessage = 'Preenchimento automático indisponível.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInvalidCnpj = _state == _CnpjLookupState.invalidCnpj;
    final isLoading = _state == _CnpjLookupState.loading;
    final showHint = _errorMessage != null;
    final hintColor = isInvalidCnpj
        ? theme.colorScheme.error
        : const Color(0xFFFBBF24); // VeraProbColors.delayed (amber)

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _cnpjController,
          decoration: InputDecoration(
            labelText: 'CNPJ',
            errorText: isInvalidCnpj ? _errorMessage : null,
            suffixIcon: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: _onCnpjChanged,
        ),
        if (showHint && !isInvalidCnpj)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Semantics(
              liveRegion: true,
              label: _errorMessage,
              child: Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(color: hintColor),
              ),
            ),
          ),
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.companyNameController,
          decoration: const InputDecoration(labelText: 'Razão Social'),
        ),
      ],
    );
  }
}
