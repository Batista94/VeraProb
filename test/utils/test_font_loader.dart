import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads local fonts from assets/fonts for deterministic rendering in golden tests.
///
/// This ensures that CI (Linux) and Local (Windows/macOS) use the exact same
/// font bytes, eliminating sub-pixel differences caused by system fallbacks.
Future<void> loadTestFonts() async {
  final fontLoader = FontLoader('Lato');

  final regular = File('assets/fonts/Lato-Regular.ttf').readAsBytesSync();
  fontLoader.addFont(Future.value(regular.buffer.asByteData()));

  final bold = File('assets/fonts/Lato-Bold.ttf').readAsBytesSync();
  fontLoader.addFont(Future.value(bold.buffer.asByteData()));

  await fontLoader.load();
}
