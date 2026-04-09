import 'dart:io';

// ignore_for_file: avoid_print

void main() {
  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    print('ERROR: coverage/lcov.info not found');
    exit(1);
  }

  final lines = lcovFile.readAsLinesSync();
  final Map<String, ({int found, int hit})> fileData = {};

  String currentFile = '';
  int fileFound = 0;
  int fileHit = 0;

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3).replaceAll('\\', '/');
      fileFound = 0;
      fileHit = 0;
    } else if (line == 'end_of_record') {
      fileData[currentFile] = (found: fileFound, hit: fileHit);
    } else if (line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        fileFound++;
        if (int.tryParse(parts[1]) != null && int.parse(parts[1]) > 0) {
          fileHit++;
        }
      }
    }
  }

  final criticalFiles = [
    'lib/domain/sla_audit/sla_ledger_entry.dart',
    'lib/domain/sla_audit/sla_penalties.dart',
    'lib/domain/sla_audit/signal_integrity_monitor.dart',
    'lib/domain/sla_audit/spoofing_detector.dart',
    'lib/domain/sla_audit/ingestion_integrity_flag.dart',
    'lib/domain/sla_audit/attestation_header.dart',
    'lib/infrastructure/sla_audit/postgres_sla_execution_query_service.dart',
    'lib/infrastructure/sla_audit/postgres_contractual_execution_state_repository.dart',
    'lib/application/sla_audit/contractual_evaluation_engine.dart',
    'lib/infrastructure/auth/supabase_auth_repository.dart',
    'lib/domain/auth/tenant_context.dart',
  ];

  print('Coverage for Critical Files (Impact-based):');
  print('-------------------------------------------');
  for (final path in criticalFiles) {
    final entry = fileData.entries.firstWhere(
      (e) => e.key.endsWith(path),
      orElse: () => const MapEntry('', (found: 0, hit: 0)),
    );

    final pct = entry.value.found > 0
        ? (entry.value.hit / entry.value.found * 100).toStringAsFixed(1)
        : 'N/A';

    print('${pct.padRight(6)}% | $path');
  }
}
