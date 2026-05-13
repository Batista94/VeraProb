import 'dart:async';
import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'utils/test_font_loader.dart';

/// Global configuration for Flutter tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Ensure we don't hit the network for fonts
  GoogleFonts.config.allowRuntimeFetching = false;

  // Load local fonts for consistent golden tests
  await loadTestFonts();

  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      forceUpdateGoldenFiles: false,
      theme: ThemeData(
        fontFamily: 'Lato',
      ),
      platformGoldensConfig: const PlatformGoldensConfig(
        enabled: false,
      ),
    ),
    run: () async {
      await testMain();
    },
  );
}
