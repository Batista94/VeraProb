import 'dart:io';

void main() {
  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    print('ERROR: coverage/lcov.info not found');
    exit(1);
  }

  final lines = lcovFile.readAsLinesSync();

  final excludePatterns = [
    RegExp(r'\.g\.dart$'),
    RegExp(r'\.freezed\.dart$'),
    RegExp(r'lib[/\\]features[/\\]'),
    RegExp(r'lib[/\\]presentation[/\\]'),
  ];

  String currentFile = '';
  bool skip = false;
  int fileFound = 0;
  int fileHit = 0;

  // Per-file data
  final Map<String, ({int found, int hit})> fileData = {};

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      skip = excludePatterns.any((p) => p.hasMatch(currentFile));
      fileFound = 0;
      fileHit = 0;
    } else if (line == 'end_of_record') {
      if (!skip && fileFound > 0) {
        fileData[currentFile] = (found: fileFound, hit: fileHit);
      }
    } else if (line.startsWith('DA:') && !skip) {
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        fileFound++;
        if (int.tryParse(parts[1]) != null && int.parse(parts[1]) > 0) {
          fileHit++;
        }
      }
    }
  }

  // Sort by uncovered lines descending
  final sorted = fileData.entries.toList()
    ..sort((a, b) {
      final aUncovered = a.value.found - a.value.hit;
      final bUncovered = b.value.found - b.value.hit;
      return bUncovered.compareTo(aUncovered);
    });

  int totalFound = 0;
  int totalHit = 0;
  for (final e in fileData.entries) {
    totalFound += e.value.found;
    totalHit += e.value.hit;
  }

  final pct = (totalHit / totalFound) * 100;
  print('=== OVERALL: $totalHit / $totalFound = ${pct.toStringAsFixed(2)}% ===\n');
  print('Files with most uncovered lines (top 30):');
  print('${'Uncovered'.padRight(10)} ${'Hit'.padRight(6)} ${'Total'.padRight(6)} ${'%'.padRight(7)} File');
  print('-' * 100);

  for (final e in sorted.take(30)) {
    final uncovered = e.value.found - e.value.hit;
    final filePct = e.value.found > 0
        ? (e.value.hit / e.value.found * 100).toStringAsFixed(1)
        : '0.0';
    // Shorten path
    final shortPath = e.key.replaceAll(r'\', '/').replaceAll(RegExp(r'.*/lib/'), 'lib/');
    print('${uncovered.toString().padRight(10)} ${e.value.hit.toString().padRight(6)} ${e.value.found.toString().padRight(6)} ${'$filePct%'.padRight(7)} $shortPath');
  }

  // Calculate what we need
  final neededHit = (totalFound * 0.60).ceil();
  final gap = neededHit - totalHit;
  print('\nNeed $neededHit hits for 60%; currently have $totalHit. Gap: $gap lines to cover.');
}
