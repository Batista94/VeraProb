/// Operational states of a trip in the PactaFlow control center.
///
/// These states form a finite state machine that drives all operational
/// visualizations — map marker colors, KPI bars, alert evaluation, and
/// timeline rendering.
enum TripStatus {
  /// Trip is programmed (from GTFS schedule or manual entry)
  scheduled,

  /// Driver + vehicle assigned, awaiting departure
  dispatched,

  /// Vehicle detected in motion along route
  enRoute,

  /// Vehicle stopped at a scheduled stop
  atStop,

  /// Delay exceeds configured threshold
  delayed,

  /// Unplanned stop or emergency
  interrupted,

  /// Trip reached final destination
  completed,

  /// Trip cancelled before or during execution
  cancelled,

  /// Scheduled trip never started
  noShow,

  /// Signals lost from the vehicle for more than threshold
  offline,

  /// Vehicle suffered a mechanical failure
  maintenance,

  /// Vehicle is manually overridden into an alternative active route
  detour;

  /// Display label in Portuguese for operators
  String get label {
    switch (this) {
      case TripStatus.scheduled:
        return 'Programada';
      case TripStatus.dispatched:
        return 'Despachada';
      case TripStatus.enRoute:
        return 'Em Trânsito';
      case TripStatus.atStop:
        return 'No Ponto';
      case TripStatus.delayed:
        return 'Atrasada';
      case TripStatus.interrupted:
        return 'Interrompida';
      case TripStatus.completed:
        return 'Completada';
      case TripStatus.cancelled:
        return 'Cancelada';
      case TripStatus.noShow:
        return 'Não Iniciada';
      case TripStatus.offline:
        return 'Sem Sinal';
      case TripStatus.maintenance:
        return 'Fora de Serviço';
      case TripStatus.detour:
        return 'Desvio Ativo';
    }
  }

  /// Whether this status represents an active (in-progress) trip
  bool get isActive {
    switch (this) {
      case TripStatus.enRoute:
      case TripStatus.atStop:
      case TripStatus.delayed:
      case TripStatus.interrupted:
      case TripStatus.detour:
      case TripStatus.offline: // it's active but bleeding
        return true;
      default:
        return false;
    }
  }

  /// Whether this status should trigger operator attention
  bool get requiresAttention {
    switch (this) {
      case TripStatus.delayed:
      case TripStatus.interrupted:
      case TripStatus.noShow:
      case TripStatus.offline:
      case TripStatus.maintenance:
        return true;
      default:
        return false;
    }
  }

  /// Whether this is a terminal state (trip is finished)
  bool get isTerminal {
    switch (this) {
      case TripStatus.completed:
      case TripStatus.cancelled:
      case TripStatus.noShow:
      case TripStatus.maintenance:
        return true;
      default:
        return false;
    }
  }

  /// Parse from database string value
  static TripStatus fromString(String value) {
    switch (value) {
      case 'scheduled':
        return TripStatus.scheduled;
      case 'dispatched':
        return TripStatus.dispatched;
      case 'en_route':
        return TripStatus.enRoute;
      case 'at_stop':
        return TripStatus.atStop;
      case 'delayed':
        return TripStatus.delayed;
      case 'interrupted':
        return TripStatus.interrupted;
      case 'completed':
        return TripStatus.completed;
      case 'cancelled':
        return TripStatus.cancelled;
      case 'no_show':
        return TripStatus.noShow;
      default:
        return TripStatus.scheduled;
    }
  }

  /// Database string representation (snake_case)
  String get dbValue {
    switch (this) {
      case TripStatus.enRoute:
        return 'en_route';
      case TripStatus.atStop:
        return 'at_stop';
      case TripStatus.noShow:
        return 'no_show';
      default:
        return name;
    }
  }
}
