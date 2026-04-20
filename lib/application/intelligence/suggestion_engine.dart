import 'package:veraprob/domain/entities/operational_suggestion.dart';

export '../../domain/entities/operational_suggestion.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

/// The Suggestion Engine provides actionable recommendations for operators.
///
/// Pure application service — no Flutter, no Riverpod, no UI concerns.
/// Consumers in the presentation layer resolve [SuggestionAction] into
/// icons and callbacks via the [SuggestionActionUi] extension.
class SuggestionEngine {
  /// Generates the single best contextual suggestion for a trip,
  /// or null if no action is needed.
  OperationalSuggestion? generateSuggestion({required OperationalTrip trip}) {
    if (!trip.requiresAttention) return null;

    final hasVehicleStopped = trip.warnings.any(
      (w) => w.type == 'vehicle_stopped',
    );
    final hasCriticalDelay = trip.warnings.any(
      (w) => w.type == 'delay_critical',
    );

    if (hasVehicleStopped) {
      return const OperationalSuggestion(
        title: 'Veículo imobilizado na via',
        description:
            'A viagem está interrompida ou o veículo não apresenta movimento. '
            'Recomenda-se cancelar esta viagem e redespachar um novo carro '
            'para não criar buraco na linha.',
        actionLabel: 'Cancelar Viagem',
        action: SuggestionAction.cancelTrip,
      );
    }

    if (hasCriticalDelay) {
      return const OperationalSuggestion(
        title: 'Atraso em cascata',
        description:
            'Um atraso acima de 10 minutos foi detectado e pode encavalar os '
            'próximos carros. Recomenda-se interromper a vigem atual e '
            'redespachar no próximo ponto regulador.',
        actionLabel: 'Interromper',
        action: SuggestionAction.interruptTrip,
      );
    }

    if (trip.status == TripStatus.delayed) {
      return const OperationalSuggestion(
        title: 'Acompanhar evolução',
        description:
            'O atraso atual ainda é contornável. Tente regularizar a operação '
            'entrando em contato com o motorista.',
        actionLabel: 'Regularizar',
        action: SuggestionAction.regularizeTrip,
      );
    }

    return null;
  }
}
