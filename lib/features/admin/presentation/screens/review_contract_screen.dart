import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../application/sla_audit/accept_by_contractor_command.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../infrastructure/sla_audit/postgres_contract_review_token_query_service.dart';
import '../../../../state/providers/contract_providers.dart';

/// Public screen for contractors to review and accept a contract.
///
/// Reached via `/review-contract?token=<token>` — no Supabase auth required.
/// Token possession is the sole authorization (INV-10 exempt: public endpoint).
///
/// Flow:
///   1. Screen loads → calls [get_contract_for_review] RPC via query service.
///   2. If invalid/expired/used: shows error card.
///   3. If valid: shows contract summary + "Aceitar Contrato" button.
///   4. On accept: calls [AcceptByContractorHandler] → stamps ledger.
///   5. On success: shows terminal success card (no navigation).
class ReviewContractScreen extends ConsumerStatefulWidget {
  final String token;

  const ReviewContractScreen({super.key, required this.token});

  @override
  ConsumerState<ReviewContractScreen> createState() =>
      _ReviewContractScreenState();
}

class _ReviewContractScreenState extends ConsumerState<ReviewContractScreen> {
  // null = loading, non-null = loaded or error
  ContractReviewSummary? _summary;
  bool _tokenValid = true; // flips false if load fails
  bool _accepting = false;
  bool _accepted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await ref
          .read(contractReviewTokenQueryServiceProvider)
          .findContractSummaryByToken(widget.token);

      if (!mounted) return;

      if (summary == null) {
        setState(() => _tokenValid = false);
      } else {
        setState(() => _summary = summary);
      }
    } catch (_) {
      if (mounted) setState(() => _tokenValid = false);
    }
  }

  Future<void> _accept() async {
    setState(() {
      _accepting = true;
      _error = null;
    });

    try {
      await ref
          .read(acceptByContractorHandlerProvider)
          .handle(AcceptByContractorCommand(token: widget.token));

      if (!mounted) return;
      setState(() {
        _accepting = false;
        _accepted = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _accepting = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PactaFlowColors.background,
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: Card(
              color: PactaFlowColors.surface,
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Loading state
    if (_summary == null && _tokenValid) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Verificando link...'),
        ],
      );
    }

    // Invalid / expired token
    if (!_tokenValid) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off, color: PactaFlowColors.error, size: 48),
          const SizedBox(height: 16),
          Text('Link Inválido', style: PactaFlowTypography.sectionTitle),
          const SizedBox(height: 8),
          Text(
            'Este link de revisão é inválido, expirou ou o contrato já foi aceito.',
            style: PactaFlowTypography.bodyMedium.copyWith(
              color: PactaFlowColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // Success state (terminal)
    if (_accepted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: PactaFlowColors.success,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            'Contrato Aceito!',
            style: PactaFlowTypography.sectionTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Sua aceitação foi registrada com sucesso.\nA operadora foi notificada.',
            style: PactaFlowTypography.bodyMedium.copyWith(
              color: PactaFlowColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // Contract summary + accept button
    final s = _summary!;
    final fmt = DateFormat('dd/MM/yyyy');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.description_outlined,
          color: PactaFlowColors.primary,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          'Revisão de Contrato',
          style: PactaFlowTypography.sectionTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Revise os dados abaixo e confirme o aceite do contrato.',
          style: PactaFlowTypography.bodyMedium.copyWith(
            color: PactaFlowColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _InfoRow(label: 'Contrato', value: s.name),
        _InfoRow(label: 'Contratante', value: s.contractorName),
        _InfoRow(
          label: 'Vigência',
          value:
              '${fmt.format(s.validFromUtc)} – ${fmt.format(s.validUntilUtc)}',
        ),
        if (s.financialCeilingCents != null)
          _InfoRow(
            label: 'Teto Financeiro',
            value: _formatCurrency(s.financialCeilingCents!),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: PactaFlowColors.error, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: _accepting ? null : _accept,
          icon: _accepting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.handshake_outlined),
          label: Text(_accepting ? 'Registrando...' : 'Aceitar Contrato'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Ao aceitar, você confirma que leu e concorda com os termos deste contrato.',
          style: PactaFlowTypography.bodySmall.copyWith(
            color: PactaFlowColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _formatCurrency(int cents) {
    final value = cents / 100.0;
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: PactaFlowTypography.bodyMedium.copyWith(
                color: PactaFlowColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: PactaFlowTypography.bodyMedium)),
        ],
      ),
    );
  }
}
