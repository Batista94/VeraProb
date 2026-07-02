import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/info_tooltip.dart';

Widget _buildSubject(InfoTooltip widget, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? AppTheme.darkTheme,
    home: Scaffold(body: Center(child: widget)),
  );
}

void main() {
  group('InfoTooltip — default (help) variant', () {
    testWidgets('renders Icons.help_outline by default', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const InfoTooltip(message: 'Test message')),
      );
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });

    testWidgets('icon size defaults to 16.0', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const InfoTooltip(message: 'Test')),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 16.0);
    });

    testWidgets('tooltip message is set correctly', (tester) async {
      const msg = 'Alavanca Financeira: exemplo de texto';
      await tester.pumpWidget(_buildSubject(const InfoTooltip(message: msg)));
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, msg);
    });

    testWidgets('Semantics label equals message when semanticLabel is null', (
      tester,
    ) async {
      const msg = 'Texto de ajuda';
      await tester.pumpWidget(_buildSubject(const InfoTooltip(message: msg)));
      final semantics = tester.getSemantics(find.byType(InfoTooltip));
      expect(semantics.label, msg);
    });
  });

  group('InfoTooltip — warning variant', () {
    testWidgets('renders Icons.warning_amber_rounded by default for warning', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(
            message: 'Sem geofence',
            variant: InfoTooltipVariant.warning,
          ),
        ),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('custom icon overrides variant default', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(
            message: 'Sem geofence',
            variant: InfoTooltipVariant.warning,
            icon: Icons.location_off,
          ),
        ),
      );
      expect(find.byIcon(Icons.location_off), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('icon color is VeraProbColors.warning', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(
            message: 'Sem geofence',
            variant: InfoTooltipVariant.warning,
            icon: Icons.location_off,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, VeraProbColors.warning);
    });

    testWidgets('custom iconColor overrides variant default color', (
      tester,
    ) async {
      const customColor = Color(0xFFFF0000);
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(
            message: 'Test',
            variant: InfoTooltipVariant.warning,
            iconColor: customColor,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, customColor);
    });
  });

  group('InfoTooltip — info variant', () {
    testWidgets('renders Icons.info_outline', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(message: 'Info', variant: InfoTooltipVariant.info),
        ),
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('icon color is VeraProbColors.info', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(message: 'Info', variant: InfoTooltipVariant.info),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, VeraProbColors.info);
    });
  });

  group('InfoTooltip — error variant', () {
    testWidgets('renders Icons.error_outline', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(
            message: 'Error',
            variant: InfoTooltipVariant.error,
          ),
        ),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('InfoTooltip — success variant', () {
    testWidgets('renders Icons.check_circle_outline', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(
            message: 'Success',
            variant: InfoTooltipVariant.success,
          ),
        ),
      );
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('InfoTooltip — size override', () {
    testWidgets('iconSize 12 produces a 12px icon', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const InfoTooltip(message: 'KPI', iconSize: 12)),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 12.0);
    });

    testWidgets('iconSize 20 produces a 20px icon', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const InfoTooltip(message: 'Large', iconSize: 20)),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 20.0);
    });
  });

  group('InfoTooltip — accessibility', () {
    testWidgets('semanticLabel overrides message in Semantics node', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(
            message: 'Texto longo para tooltip',
            semanticLabel: 'Rótulo acessível curto',
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(InfoTooltip));
      expect(semantics.label, 'Rótulo acessível curto');
    });

    testWidgets('inner Icon semanticLabel is empty string', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const InfoTooltip(message: 'Test')),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.semanticLabel, '');
    });
  });

  group('InfoTooltip — help variant color adapts to theme', () {
    testWidgets('dark theme: color derives from onSurface at 45% alpha', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(message: 'Test'),
          theme: AppTheme.darkTheme,
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      final buildContext = tester.element(find.byType(Icon));
      final expectedColor = Theme.of(
        buildContext,
      ).colorScheme.onSurface.withValues(alpha: 0.45);
      expect(icon.color, expectedColor);
    });

    testWidgets('warning variant color is correct in dark theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          const InfoTooltip(
            message: 'Warning',
            variant: InfoTooltipVariant.warning,
          ),
          theme: AppTheme.darkTheme,
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, VeraProbColors.warning);
    });
  });
}
