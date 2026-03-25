// ignore_for_file: avoid_print
import 'dart:io';

void main() {
  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    print('ERROR: coverage/lcov.info not found');
    exit(1);
  }

  final lines = lcovFile.readAsLinesSync();

  // Exclusion patterns matching the CI filter
  final excludePatterns = [
    RegExp(r'\.g\.dart$'),
    RegExp(r'\.freezed\.dart$'),
    RegExp(r'lib[/\\]features[/\\]'),
    RegExp(r'lib[/\\]presentation[/\\]'),
  ];

  int totalFound = 0;
  int totalHit = 0;
  String currentFile = '';
  bool skip = false;

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      skip = excludePatterns.any((p) => p.hasMatch(currentFile));
    } else if (line.startsWith('DA:') && !skip) {
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        totalFound++;
        if (int.tryParse(parts[1]) != null && int.parse(parts[1]) > 0) {
          totalHit++;
        }
      }
    }
  }

  if (totalFound == 0) {
    print('No coverage data found after filtering.');
    exit(1);
  }

  final pct = (totalHit / totalFound) * 100;
  print(
    'Filtered coverage: $totalHit / $totalFound lines = ${pct.toStringAsFixed(4)}%',
  );
  print(pct >= 60 ? 'PASS (>= 60%)' : 'FAIL (< 60%)');
}
