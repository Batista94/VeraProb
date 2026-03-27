/// How closely a vehicle follows its assigned GTFS route shape.
enum RouteAdherence {
  /// Distance to route shape ≤ 80 m.
  onRoute,

  /// Distance between 80 m and 200 m.
  minorDeviation,

  /// Distance > 200 m for > 60 s consecutively.
  offRoute;

  String get label {
    switch (this) {
      case RouteAdherence.onRoute:
        return 'Na Rota';
      case RouteAdherence.minorDeviation:
        return 'Desvio Leve';
      case RouteAdherence.offRoute:
        return 'Fora da Rota';
    }
  }

  /// Whether this state should trigger operator attention.
  bool get requiresAttention => this == RouteAdherence.offRoute;
}
