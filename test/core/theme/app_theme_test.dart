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
  when(() => response.statusCode).thenReturn(404); // Not found para forçar fallback gracioso
  when(() => response.contentLength).thenReturn(0);
}

void main() {
  // Garantir que mocks e configurações de rede ocorram antes de qualquer acesso ao AppTheme
  _setupMocks();
  GoogleFonts.config.allowRuntimeFetching = false;
  
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTheme Coverage', () {
    test('VeraProbColors access', () {
      expect(VeraProbColors.background, const Color(0xFF0F172A));
      expect(VeraProbColors.primary, const Color(0xFF2DD4BF));
      expect(VeraProbColors.success, VeraProbColors.onTime);
      expect(VeraProbColors.warning, VeraProbColors.delayed);
      expect(VeraProbColors.error, VeraProbColors.critical);
      expect(VeraProbColors.info, VeraProbColors.scheduled);
    });

    test('VeraProbSpacing access', () {
      expect(VeraProbSpacing.xs, 4.0);
      expect(VeraProbSpacing.sectionPadding, const EdgeInsets.all(16.0));
      expect(
        VeraProbSpacing.cardPadding,
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      );
    });

    test('VeraProbTypography access', () {
      expect(VeraProbTypography.kpiValue.fontSize, 28);
      expect(VeraProbTypography.kpiLabel.fontWeight, FontWeight.w600);
      expect(VeraProbTypography.sectionTitle.color, VeraProbColors.textPrimary);
      expect(VeraProbTypography.bodyMedium.fontSize, 13);
      expect(VeraProbTypography.bodySmall.fontSize, 12);
      expect(VeraProbTypography.caption.fontSize, 11);
      expect(VeraProbTypography.badge.letterSpacing, 0.5);
      expect(VeraProbTypography.dataValue.fontWeight, FontWeight.w600);
      expect(VeraProbTypography.fieldLabel.fontSize, 11);
    });

    test('AppTheme.darkTheme properties', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, VeraProbColors.background);
      expect(theme.colorScheme.primary, VeraProbColors.primary);
    });

    test('AppTheme.lightTheme properties', () {
      final theme = AppTheme.lightTheme;
      expect(theme.brightness, Brightness.light);
    });

    test('AppTheme helpers', () {
      expect(AppTheme.primaryColor, VeraProbColors.primary);
      expect(AppTheme.surfaceColor, VeraProbColors.background);
      expect(AppTheme.primaryGradient, isA<Gradient>());
    });
  });
}
