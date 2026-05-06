import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Standalone CNPJ autofill field that uses the proxy-based lookup service.
///
/// Routes through `super-admin-proxy` Edge Function to bypass CORS (INV-14).
/// The old direct-HTTP implementation (`ReceitaWsService`) is deprecated.
class CnpjAutofillField extends ConsumerStatefulWidget {
  final TextEditingController companyNameController;

  const CnpjAutofillField({
    super.key,
    required this.companyNameController,
  });

  @override
  ConsumerState<CnpjAutofillField> createState() => _CnpjAutofillFieldState();
}

class _CnpjAutofillFieldState extends ConsumerState<CnpjAutofillField> {
  final _cnpjController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;

  @override
  void dispose() {
    _cnpjController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onCnpjChanged(String value) {
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
      _isLoading = true;
    });

    // INV-14: Route through Edge Function proxy (no direct browser HTTP).
    final service = ref.read(cnpjLookupServiceProvider);
    final data = await service.lookup(digits);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      // Graceful degradation: If data is null (API failed), we do nothing and
      // the user can manually type in the name field, keeping UI unblocked.
      if (data != null && data.legalName != null && data.legalName!.isNotEmpty) {
        widget.companyNameController.text = data.legalName!;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _cnpjController,
          decoration: InputDecoration(
            labelText: 'CNPJ',
            suffixIcon: _isLoading 
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
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.companyNameController,
          decoration: const InputDecoration(
            labelText: 'Razão Social',
          ),
        ),
      ],
    );
  }
}
