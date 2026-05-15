import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'package:veraprob/features/admin/providers/trips_provider.dart';
import 'package:veraprob/presentation/shared/ui/skeleton_list_loader.dart';

class TimecardReportsScreen extends ConsumerWidget {
  const TimecardReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(tripsListProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Relatório de Ponto Eletrônico',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text('Histórico de viagens e horas trabalhadas.'),
            const SizedBox(height: 24),
            Expanded(
              child: switch (tripsAsync) {
                AsyncData(:final value) => () {
                  final trips = value;
                  if (trips.isEmpty) {
                    return const Center(
                      child: Text('Nenhuma viagem registrada.'),
                    );
                  }

                  // Calculate total duration (for valid completed trips)
                  final totalDuration = trips.fold<Duration>(Duration.zero, (
                    prev,
                    trip,
                  ) {
                    if (trip.endTime != null) {
                      return prev + trip.endTime!.difference(trip.startTime);
                    }
                    return prev;
                  });

                  final totalHours = totalDuration.inHours;
                  final totalMinutes = totalDuration.inMinutes.remainder(60);

                  return Column(
                    children: [
                      // Summary Card
                      Card(
                        color: Colors.indigo.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    'Total Viagens',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  Text(
                                    '${trips.length}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    'Horas Totais',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  Text(
                                    '${totalHours}h ${totalMinutes}m',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // List of Trips
                      Expanded(
                        child: ListView.builder(
                          itemCount: trips.length,
                          itemBuilder: (context, index) {
                            final trip = trips[index];
                            final duration = trip.endTime == null
                                ? 'Em andamento'
                                : '${trip.endTime!.difference(trip.startTime).inMinutes} min';

                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  trip.status == 'active'
                                      ? Icons.directions_bus
                                      : Icons.check_circle,
                                  color: trip.status == 'active'
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                title: Text('Linha: ${trip.routeId}'),
                                subtitle: Text(
                                  'Motorista: ${trip.driverId}\nInício: ${trip.startTime.toIso8601String().substring(11, 16)} - Fim: ${trip.endTime?.toIso8601String().substring(11, 16) ?? '-'}',
                                ),
                                trailing: Text(duration),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }(),
                AsyncLoading() => const SkeletonListLoader(),
                AsyncError(:final error, :final stackTrace) => () {
                  LoggerService().error(
                    'Falha ao carregar relatórios',
                    error: error,
                    stackTrace: stackTrace,
                  );
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'Não foi possível carregar os relatórios agora.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tente novamente mais tarde.',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
