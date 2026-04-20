import 'package:equatable/equatable.dart';

class Trip extends Equatable {
  final String id;
  final String driverId;
  final String routeId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // active, completed

  const Trip({
    required this.id,
    required this.driverId,
    required this.routeId,
    required this.startTime,
    this.endTime,
    this.status = 'active',
  });

  Trip copyWith({
    String? id,
    String? driverId,
    String? routeId,
    DateTime? startTime,
    DateTime? endTime,
    String? status,
  }) {
    return Trip(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      routeId: routeId ?? this.routeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
    id,
    driverId,
    routeId,
    startTime,
    endTime,
    status,
  ];
}
