/// Presentation-friendly representation of [TripStatus].
///
/// This exists solely to satisfy the architectural requirement that the
/// Presentation Layer (`lib/features/`) never imports the Domain Layer directly.
enum TripStatusView {
  scheduled,
  enRoute,
  delayed,
  atStop,
  interrupted,
  noShow,
  maintenance,
  completed,
  cancelled;

  String get label => switch (this) {
    scheduled => 'PROGRAMADO',
    enRoute => 'EM ROTA',
    delayed => 'ATRASADO',
    atStop => 'NO PONTO',
    interrupted => 'INTERROMPIDO',
    noShow => 'NO-SHOW',
    maintenance => 'MANUTENÇÃO',
    completed => 'CONCLUÍDO',
    cancelled => 'CANCELADO',
  };

  bool get isActive => switch (this) {
    scheduled || enRoute || delayed || atStop || interrupted => true,
    noShow || maintenance || completed || cancelled => false,
  };
}
