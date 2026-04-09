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

  print('Coverage for Infrastructure Files (Postgres):');
  print('-------------------------------------------');
  final infraDir = Directory('lib/infrastructure/sla_audit');
  final files = infraDir.listSync().whereType<File>().where(
    (f) => f.path.contains('postgres_'),
  );

  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final entry = fileData.entries.firstWhere(
      (e) => e.key.endsWith(path),
      orElse: () => const MapEntry('', (found: 0, hit: 0)),
    );

    final pct = entry.value.found > 0
        ? (entry.value.hit / entry.value.found * 100).toStringAsFixed(1)
        : '0.0';

    print('${pct.padRight(6)}% | $path');
  }
}
