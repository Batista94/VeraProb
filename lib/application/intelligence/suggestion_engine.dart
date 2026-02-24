import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/operational_suggestion.dart';
import '../../../domain/entities/operational_trip.dart';
import '../../../domain/enums/trip_status.dart';
import '../../../state/providers/fleet_providers.dart';

/// The Suggestion Engine provides actionable recommendations for operators.
///
/// It looks at the enriched [OperationalTrip] (which contains warnings and severity)
/// and proposes the single best action to resolve the situation.
class SuggestionEngine {
  /// Generates a contextual suggestion for a trip, or null if everything is fine.
  OperationalSuggestion? generateSuggestion({
    required WidgetRef ref,
    required BuildContext context,
    required OperationalTrip trip,
  }) {
    // If trip is already terminal or no attention needed, no suggestion
    if (!trip.requiresAttention) return null;

    final hasCriticalDelay = trip.warnings.any(
      (w) => w.type == 'delay_critical',
    );
    final hasVehicleStopped = trip.warnings.any(
      (w) => w.type == 'vehicle_stopped',
    );

    if (hasVehicleStopped) {
      return OperationalSuggestion(
        title: 'Veículo imobilizado na via',
        description:
            'A viagem está interrompida ou o veículo não apresenta movimento. Recomenda-se cancelar esta viagem e redespachar um novo carro para não criar buraco na linha.',
        actionLabel: 'Cancelar Viagem',
        actionIcon: Icons.cancel_outlined,
        onExecute: () => _executeStatusChange(
          ref,
          context,
          trip.id,
          TripStatus.cancelled,
          'Cancelado via auto-sugestão (Veículo parado)',
        ),
      );
    }

    if (hasCriticalDelay) {
      return OperationalSuggestion(
        title: 'Atraso em cascata',
        description:
            'Um atraso acima de 10 minutos foi detectado e pode encavalar os próximos carros. Recomenda-se interromper a vigem atual e redespachar no próximo ponto regulador.',
        actionLabel: 'Interromper',
        actionIcon: Icons.pause_circle_outline,
        onExecute: () => _executeStatusChange(
          ref,
          context,
          trip.id,
          TripStatus.interrupted,
          'Interrompido via auto-sugestão (Atraso crítico)',
        ),
      );
    }

    // Default catch-all for mild attention
    if (trip.status == TripStatus.delayed) {
      return OperationalSuggestion(
        title: 'Acompanhar evolução',
        description:
            'O atraso atual ainda é contornável. Tente regularizar a operação entrando em contato com o motorista.',
        actionLabel: 'Regularizar',
        actionIcon: Icons.check_circle_outline,
        onExecute: () => _executeStatusChange(
          ref,
          context,
          trip.id,
          TripStatus.enRoute,
          'Regularizado via auto-sugestão (Acompanhado)',
        ),
      );
    }

    return null;
  }

  void _executeStatusChange(
    WidgetRef ref,
    BuildContext context,
    String tripId,
    TripStatus newStatus,
    String reason,
  ) {
    final control = ref.read(operationalControlProvider);
    control.updateTripStatus(tripId, newStatus, reason: reason);
    triggerUIRefresh(ref);
  }
}
