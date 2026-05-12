import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'utils/test_font_loader.dart';

/// Global configuration for Flutter tests.
///
/// This runs before each test file in the directory.
/// We use it to:
/// 1. Disable runtime fetching of Google Fonts (deterministic fonts).
/// 2. Load local Lato fonts from assets.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Ensure we don't hit the network for fonts
  GoogleFonts.config.allowRuntimeFetching = false;

  // Load local fonts for consistent golden tests
  await loadTestFonts();

  await testMain();
}
