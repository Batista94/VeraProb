import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/infrastructure/observability/analytics_service.dart';
import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_provider.dart';
import 'package:veraprob/presentation/sandbox/widgets/dashboard/sandbox_results_dashboard.dart';
import 'package:veraprob/presentation/sandbox/widgets/sandbox_banner.dart';
import 'package:veraprob/presentation/sandbox/widgets/wizard/sandbox_wizard_form.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/sandbox_providers.dart';

/// Host screen for the SLA Sandbox (ROI Simulator).
///
/// URL-addressable at `/admin/hub/contracts/:contractId/sandbox`.
/// Resets simulation state on mount/dispose to prevent A/B Delta leakage.
/// Sandbox query providers are watched only here (lazy compute).
class SlaSandboxScreen extends ConsumerStatefulWidget {
  final String contractId;

  const SlaSandboxScreen({super.key, required this.contractId});

  @override
  ConsumerState<SlaSandboxScreen> createState() => _SlaSandboxScreenState();
}

class _SlaSandboxScreenState extends ConsumerState<SlaSandboxScreen> {
  String? _activeSessionId;
  ProviderContainer? _container;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      resetSandboxSimulationState(ref);
      unawaited(
        AnalyticsService.track(
          VeraProbEvent.sandboxRouteEntered,
          properties: {
            'contract_id': widget.contractId,
            'user_role': ref.read(currentUserRoleProvider).name,
            'user_id': ref.read(currentOperatorIdProvider) ?? '',
          },
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context);
  }

  @override
  void dispose() {
    final c = _container;
    if (c != null) {
      resetSandboxSimulationStateOn(c);
    }
    super.dispose();
  }

  void _exitSandbox() {
    resetSandboxSimulationState(ref);
    setState(() => _activeSessionId = null);
    if (!mounted) return;
    context.go(AdminNavRoute(AdminNav.contracts).path);
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(contractDetailProvider(widget.contractId));
    final simAsync = ref.watch(sandboxSimulationControllerProvider);
    final sessionId = _activeSessionId ?? simAsync.asData?.value;

    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Voltar',
                onPressed: _exitSandbox,
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              Text('Simular ROI', style: VeraProbTypography.heading),
            ],
          ),
          const SizedBox(height: VeraProbSpacing.md),
          Expanded(
            child: switch (detailAsync) {
              AsyncLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
              AsyncError() => const Center(
                child: Text(
                  'Não foi possível carregar o contrato para simulação.',
                  style: TextStyle(color: VeraProbColors.error),
                ),
              ),
              AsyncData(:final value) =>
                value == null
                    ? const Center(child: Text('Contrato não encontrado.'))
                    : sessionId != null
                    ? _buildResults(sessionId)
                    : _buildWizard(value.summary.name),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWizard(String contractName) {
    return SingleChildScrollView(
      child: SandboxWizardForm(
        contracts: [
          SandboxContractOption(id: widget.contractId, label: contractName),
        ],
        lockedContractId: widget.contractId,
        onSimulationStarted: (id) {
          setState(() => _activeSessionId = id);
        },
      ),
    );
  }

  Widget _buildResults(String sessionId) {
    final sessionAsync = ref.watch(sandboxSessionDetailProvider(sessionId));
    final resultsAsync = ref.watch(sandboxSessionResultsProvider(sessionId));

    return sessionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(
        child: Text(
          'Não foi possível carregar a sessão de simulação.',
          style: TextStyle(color: VeraProbColors.error),
        ),
      ),
      data: (session) {
        if (session == null) {
          return const Center(child: Text('Sessão não encontrada.'));
        }
        final results = resultsAsync.asData?.value ?? const [];
        final loading = resultsAsync.isLoading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SandboxBanner(
              sessionLabel: session.sessionLabel,
              periodStartUtc: session.periodStartUtc,
              periodEndUtc: session.periodEndUtc,
              onExit: _exitSandbox,
            ),
            const SizedBox(height: VeraProbSpacing.md),
            Expanded(
              child: SingleChildScrollView(
                child: SandboxResultsDashboard(
                  session: session,
                  results: results,
                  isLoading: loading,
                  onExit: _exitSandbox,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
