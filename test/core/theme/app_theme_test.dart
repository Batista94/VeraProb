import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/core/theme/app_theme.dart';

// Mock para interceptar chamadas HTTP do GoogleFonts durante os testes
class MockHttpClient extends Mock implements HttpClient {}

class MockHttpClientRequest extends Mock implements HttpClientRequest {}

class MockHttpClientResponse extends Mock implements HttpClientResponse {}

class MockHttpHeaders extends Mock implements HttpHeaders {}

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _mockClient;
}

final _mockClient = MockHttpClient();

void _setupMocks() {
  HttpOverrides.global = TestHttpOverrides();

  final request = MockHttpClientRequest();
  final response = MockHttpClientResponse();
  final headers = MockHttpHeaders();

  registerFallbackValue(Uri());

  when(() => _mockClient.getUrl(any())).thenAnswer((_) async => request);
  when(() => request.headers).thenReturn(headers);
  when(() => request.close()).thenAnswer((_) async => response);
  when(() => response.statusCode).thenReturn(404);
  when(() => response.contentLength).thenReturn(0);
}

void main() {
  // Garantir que mocks e configurações de rede ocorram antes de qualquer acesso ao AppTheme
  _setupMocks();
  GoogleFonts.config.allowRuntimeFetching = false;

  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTheme Coverage', () {
    testWidgets('VeraProbColors access', (WidgetTester tester) async {
      expect(VeraProbColors.background, const Color(0xFF09090B));
      expect(VeraProbColors.surface, const Color(0xFF101013));
      expect(VeraProbColors.surfaceElevated, const Color(0xFF18181D));
      expect(VeraProbColors.primary, const Color(0xFF6E7CF6));
      expect(VeraProbColors.accent, const Color(0xFF93A0FF));
      expect(VeraProbColors.secondary, const Color(0xFF5EEAD4));
      expect(VeraProbColors.textPrimary, const Color(0xFFE4E4E9));
      expect(VeraProbColors.textSecondary, const Color(0xFF9B9BA6));
      expect(VeraProbColors.textDisabled, const Color(0xFF4E4E58));
      expect(VeraProbColors.success, VeraProbColors.onTime);
      expect(VeraProbColors.warning, VeraProbColors.delayed);
      expect(VeraProbColors.error, VeraProbColors.critical);
      expect(VeraProbColors.info, VeraProbColors.scheduled);
      expect(VeraProbColors.verdictAction, const Color(0xFF8B5CF6));
      await tester.pumpAndSettle();
    });

    testWidgets('VeraProbRadii access', (WidgetTester tester) async {
      expect(VeraProbRadii.sm, 4.0);
      expect(VeraProbRadii.md, 8.0);
      expect(VeraProbRadii.lg, 12.0);
      expect(VeraProbRadii.xl, 16.0);
      expect(VeraProbRadii.pill, 999.0);
      await tester.pumpAndSettle();
    });

    testWidgets('VeraProbMotion access', (WidgetTester tester) async {
      expect(VeraProbMotion.fast, const Duration(milliseconds: 150));
      expect(VeraProbMotion.base, const Duration(milliseconds: 200));
      expect(VeraProbMotion.slow, const Duration(milliseconds: 300));
      expect(VeraProbMotion.curve, isA<Curve>());
      await tester.pumpAndSettle();
    });

    testWidgets('VeraProbBreakpoints constants', (WidgetTester tester) async {
      expect(VeraProbBreakpoints.compact, 600.0);
      expect(VeraProbBreakpoints.medium, 900.0);
      expect(VeraProbBreakpoints.wide, 1100.0);
      expect(VeraProbBreakpoints.maxContent, 1600.0);
      await tester.pumpAndSettle();
    });

    testWidgets('VeraProbSpacing access', (WidgetTester tester) async {
      expect(VeraProbSpacing.xs, 4.0);
      expect(VeraProbSpacing.sectionPadding, const EdgeInsets.all(16.0));
      expect(
        VeraProbSpacing.cardPadding,
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('VeraProbTypography access', (WidgetTester tester) async {
      expect(VeraProbTypography.kpiValue.fontSize, 28);
      expect(VeraProbTypography.kpiLabel.fontWeight, FontWeight.w600);
      expect(VeraProbTypography.sectionTitle.color, VeraProbColors.textPrimary);
      expect(VeraProbTypography.bodyMedium.fontSize, 13);
      expect(VeraProbTypography.bodySmall.fontSize, 12);
      expect(VeraProbTypography.caption.fontSize, 11);
      expect(VeraProbTypography.badge.letterSpacing, 0.5);
      expect(VeraProbTypography.dataValue.fontWeight, FontWeight.w600);
      expect(VeraProbTypography.fieldLabel.fontSize, 11);
      await tester.pumpAndSettle();
    });

    testWidgets('AppTheme.darkTheme properties', (WidgetTester tester) async {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, VeraProbColors.background);
      expect(theme.colorScheme.primary, VeraProbColors.primary);
      await tester.pumpAndSettle();
    });

    testWidgets('AppTheme helpers', (WidgetTester tester) async {
      expect(AppTheme.primaryColor, VeraProbColors.primary);
      expect(AppTheme.surfaceColor, VeraProbColors.background);
      expect(AppTheme.primaryGradient, isA<Gradient>());
      await tester.pumpAndSettle();
    });
  });
}
