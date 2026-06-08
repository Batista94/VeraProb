import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';

class OnboardingStep {
  final String label;
  final String description;
  final bool isFulfilled;
  final AdminNav destination;

  const OnboardingStep({
    required this.label,
    required this.description,
    required this.isFulfilled,
    required this.destination,
  });
}

class OnboardingProgress {
  final List<OnboardingStep> steps;
  final int completedCount;
  final bool isComplete;

  const OnboardingProgress({
    required this.steps,
    required this.completedCount,
    required this.isComplete,
  });
}

final onboardingProgressProvider = Provider<OnboardingProgress>((ref) {
  final contractors = ref.watch(contractorListProvider).value ?? [];
  final zones = ref.watch(operationalZonesProvider).value ?? [];
  final contracts = ref.watch(contractListProvider).value ?? [];
  final templates = ref.watch(slaTemplatesProvider).value ?? [];

  final hasContractors = contractors.isNotEmpty;
  final hasZones = zones.isNotEmpty;
  final hasContracts = contracts.isNotEmpty;
  final hasSlaTemplates = templates.isNotEmpty;
  final hasPlans = contracts.any(
    (c) => c.planCount > 0 || c.activePlanVersion > 0,
  );

  final steps = [
    OnboardingStep(
      label: 'Contratantes',
      description: 'Cadastre a entidade contratante do serviço.',
      isFulfilled: hasContractors,
      destination: AdminNav.contractors,
    ),
    OnboardingStep(
      label: 'Zonas Operacionais',
      description: 'Defina as áreas geofundadas da operação.',
      isFulfilled: hasZones,
      destination: AdminNav.zones,
    ),
    OnboardingStep(
      label: 'Contratos',
      description: 'Registre o primeiro contrato operacional.',
      isFulfilled: hasContracts,
      destination: AdminNav.contracts,
    ),
    OnboardingStep(
      label: 'Modelos SLA',
      description: 'Configure as regras de tolerância e multas.',
      isFulfilled: hasSlaTemplates,
      destination: AdminNav.slaTemplates,
    ),
    OnboardingStep(
      label: 'Planos Operacionais',
      description: 'Declare o plano vinculando turnos e regras.',
      isFulfilled: hasPlans,
      destination: AdminNav
          .contracts, // Declaring a plan is done from the contract detail screen
    ),
  ];

  final completedCount = steps.where((s) => s.isFulfilled).length;
  final isComplete = completedCount == steps.length;

  return OnboardingProgress(
    steps: steps,
    completedCount: completedCount,
    isComplete: isComplete,
  );
});
