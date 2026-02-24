import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers.dart';
import '../../driver/domain/entities/driver.dart';
import 'driver_screen.dart';

class DriverSelectionScreen extends ConsumerStatefulWidget {
  const DriverSelectionScreen({super.key});

  @override
  ConsumerState<DriverSelectionScreen> createState() =>
      _DriverSelectionScreenState();
}

class _DriverSelectionScreenState extends ConsumerState<DriverSelectionScreen> {
  Driver? _selectedDriver;

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(driverListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Identificação do Motorista')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.badge, size: 80, color: Colors.blueGrey),
            const SizedBox(height: 32),
            const Text(
              'Quem é você?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            driversAsync.when(
              data: (drivers) => DropdownButtonFormField<Driver>(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Selecione seu nome',
                ),
                initialValue: _selectedDriver,
                items: drivers.map((driver) {
                  return DropdownMenuItem(
                    value: driver,
                    child: Text(driver.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDriver = value;
                  });
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Text('Erro ao carregar motoristas: $err'),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: _selectedDriver == null
                  ? null
                  : () {
                      // Save selected driver to user session (Provider)
                      ref.read(currentDriverProvider.notifier).state =
                          _selectedDriver;

                      // Navigate to Dashboard
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const DriverScreen()),
                      );
                    },
              child: const Text('CONFIRMAR'),
            ),
          ],
        ),
      ),
    );
  }
}
