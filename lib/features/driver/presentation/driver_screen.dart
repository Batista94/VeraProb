import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers.dart';

import 'driver_selection_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';

class DriverScreen extends ConsumerStatefulWidget {
  const DriverScreen({super.key});

  @override
  ConsumerState<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends ConsumerState<DriverScreen> {
  // Simulating data from Admin
  final List<String> _availableLines = [
    '809U-10 (Cidade Universitária / Metrô Barra Funda)',
    '875C-10 (Term. Lapa / Metrô Santa Cruz)',
    '917H-10 (Term. Pirituba / Metrô Vila Mariana)',
    '701U-10 (Cidade Universitária / Metrô Santana)',
  ];

  String? _selectedLine;
  bool _isTracking = false;

  // ignore: unused_field
  String _statusMessage = 'Pronto para iniciar';
  late FlutterTts _flutterTts;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("pt-BR");
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  bool get _isNightMode {
    final hour = DateTime.now().hour;
    return hour >= 18 || hour < 6;
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(currentDriverProvider);
    final isNight = _isNightMode;
    final bgColor = isNight ? const Color(0xFF1E1E1E) : Colors.white;
    final cardColor = isNight
        ? const Color(0xFF2C2C2C)
        : Colors.blue.withValues(alpha: 0.05);
    final textColor = isNight ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Motorista - BusFlow'),
        backgroundColor: isNight ? const Color(0xFF2C2C2C) : Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Logout logic: clear driver and go back
              ref.read(currentDriverProvider.notifier).state = null;
              // Navigate back to Selection Screen (since we replaced route, we push a new one or pop?)
              // Since main_driver.dart starts with Selection, and we pushedReplacement,
              // we can pushReplacement back to Selection.
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const DriverSelectionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Section: Driver Info & Selection
          Container(
            padding: const EdgeInsets.all(16),
            color: cardColor,
            child: Column(
              children: [
                if (driver != null)
                  Row(
                    children: [
                      const CircleAvatar(radius: 24, child: Icon(Icons.person)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: textColor,
                            ),
                          ),
                          Text(
                            'CNH: ${driver.licenseNumber}',
                            style: TextStyle(
                              color: isNight
                                  ? Colors.grey[400]
                                  : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Selecione a Linha',
                    labelStyle: TextStyle(
                      color: isNight ? Colors.grey[400] : Colors.grey[700],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isNight ? const Color(0xFF3C3C3C) : Colors.white,
                    prefixIcon: Icon(
                      Icons.directions_bus,
                      color: isNight ? Colors.white70 : Colors.grey,
                    ),
                  ),
                  dropdownColor: isNight
                      ? const Color(0xFF3C3C3C)
                      : Colors.white,
                  value: _selectedLine,
                  style: TextStyle(color: textColor, fontSize: 16),
                  items: _availableLines.map((line) {
                    return DropdownMenuItem(
                      value: line.split(' ')[0],
                      child: Text(line, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: _isTracking
                      ? null
                      : (value) {
                          setState(() {
                            _selectedLine = value;
                          });
                        },
                ),
              ],
            ),
          ),

          // Middle Section: Status / Speedometer
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: isNight
                  ? Colors.black
                  : (_isTracking ? Colors.green.shade50 : Colors.grey.shade50),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isTracking ? Icons.satellite_alt : Icons.location_off,
                    size: 80,
                    color: _isTracking ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isTracking ? 'EM VIAGEM' : 'AGUARDANDO INÍCIO',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: _isTracking ? Colors.green : Colors.grey,
                    ),
                  ),
                  if (_isTracking) ...[
                    const SizedBox(height: 24),
                    Consumer(
                      builder: (context, ref, _) {
                        final locationAsync = ref.watch(
                          userLocationStreamProvider,
                        );
                        return locationAsync.when(
                          data: (pos) {
                            final speedKmH = (pos.speed * 3.6).toInt();
                            return Column(
                              children: [
                                Text(
                                  '$speedKmH',
                                  style: TextStyle(
                                    fontSize: 80,
                                    fontWeight: FontWeight.bold,
                                    height: 1,
                                    color: textColor,
                                  ),
                                ),
                                const Text(
                                  'km/h',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            );
                          },
                          loading: () => const CircularProgressIndicator(),
                          error: (_, _) => const Text('--'),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Section: Giant Action Button
          Expanded(
            flex: 2,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _toggleTracking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTracking ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  elevation: 8,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isTracking ? Icons.stop_circle : Icons.play_circle,
                      size: 64,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isTracking ? 'ENCERRAR VIAGEM' : 'INICIAR VIAGEM',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleTracking() {
    if (_selectedLine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Por favor, selecione uma linha antes de iniciar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isTracking = !_isTracking;
      _statusMessage = _isTracking ? 'Tracking Active' : 'Stopped';
    });

    if (_isTracking) {
      final driver = ref.read(currentDriverProvider);

      if (driver != null) {
        // We use the selected line as "routeId" for MVP simplicity
        ref
            .read(trackingServiceProvider)
            .startTracking(_selectedLine!, driver.id);
      } else {
        // Fallback or error handling
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro: Motorista não identificado.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Viagem iniciada na linha $_selectedLine! 🚀'),
          backgroundColor: Colors.green,
        ),
      );
      _speak('Viagem iniciada. Bom trabalho!');
    } else {
      ref.read(trackingServiceProvider).stopTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Viagem finalizada com sucesso. 🏁'),
          backgroundColor: Colors.blue,
        ),
      );
      _speak('Viagem encerrada.');
    }
  }
}
