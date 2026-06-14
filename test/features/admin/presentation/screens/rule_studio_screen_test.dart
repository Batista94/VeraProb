import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/rule_version_history_entry.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/features/admin/presentation/screens/rule_studio_screen.dart';
import 'package:veraprob/state/providers/rule_studio_providers.dart';

const _contractId = 'contract-1';

RuleVersionHistoryEntry _entry({
  required String id,
  required SlaRuleType type,
  required Map<String, dynamic> config,
  required int version,
  required bool isActive,
  bool isScheduled = false,
  DateTime? activeFrom,
  DateTime? activeTo,
}) {
  return RuleVersionHistoryEntry(
    id: id,
    ruleType: type,
    config: config,
    ruleVersion: version,
    evaluationOrder: 0,
    activeFromUtc: activeFrom ?? DateTime.utc(2026, 1, 1),
    activeToUtc: activeTo,
    isActive: isActive,
    isScheduled: isScheduled,
  );
}

Widget _host({
  required Map<SlaRuleType, RuleVersionHistoryEntry> active,
  required List<RuleVersionHistoryEntry> history,
}) {
  return ProviderScope(
    overrides: [
      activeRulesProvider(_contractId).overrideWith((ref) async => active),
      ruleHistoryProvider(_contractId).overrideWith((ref) async => history),
    ],
    child: const MaterialApp(
      home: Scaffold(body: RuleStudioScreen(contractId: _contractId)),
    ),
  );
}

void main() {
  group('RuleVersionHistoryEntry.fromJson — isScheduled', () {
    Map<String, dynamic> base() => {
      'id': 'r1',
      'rule_type': 'MAX_TOLERANCE_DELAY',
      'rule_config': {'threshold_minutes': 15},
      'rule_version': 1,
      'evaluation_order': 0,
      'active_from_utc': '2026-06-01T00:00:00Z',
      'active_to_utc': null,
      'is_active': false,
    };

    test('parses is_scheduled = true', () {
      final e = RuleVersionHistoryEntry.fromJson({
        ...base(),
        'is_scheduled': true,
      });
      expect(e.isScheduled, isTrue);
    });

    test('missing is_scheduled defaults to false', () {
      final e = RuleVersionHistoryEntry.fromJson(base());
      expect(e.isScheduled, isFalse);
    });
  });

  group('RuleStudioScreen', () {
    setUp(() {});

    testWidgets('renders active rule card with config summary and actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final active = _entry(
        id: 'a1',
        type: SlaRuleType.maxToleranceDelay,
        config: {'threshold_minutes': 15},
        version: 2,
        isActive: true,
        activeFrom: DateTime.utc(2026, 1, 1),
      );

      await tester.pumpWidget(
        _host(
          active: {SlaRuleType.maxToleranceDelay: active},
          history: [active],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Regras Ativas'), findsOneWidget);
      expect(find.text('Tolerância: 15 min'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Agendar'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Aposentar'), findsOneWidget);
    });

    testWidgets('shows scheduled-version badge when a scheduled entry exists', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final active = _entry(
        id: 'a1',
        type: SlaRuleType.maxToleranceDelay,
        config: {'threshold_minutes': 15},
        version: 2,
        isActive: true,
      );
      final scheduled = _entry(
        id: 's1',
        type: SlaRuleType.maxToleranceDelay,
        config: {'threshold_minutes': 30},
        version: 3,
        isActive: false,
        isScheduled: true,
        activeFrom: DateTime.utc(2026, 12, 1),
      );

      await tester.pumpWidget(
        _host(
          active: {SlaRuleType.maxToleranceDelay: active},
          history: [active, scheduled],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Versão agendada'), findsOneWidget);
      // History panel renders the scheduled row without crashing (NPE guard).
      expect(find.textContaining('(agendada)'), findsOneWidget);
    });

    testWidgets('empty active rules shows the empty message', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_host(active: {}, history: []));
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhuma regra ativa configurada para este contrato.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping Agendar opens the schedule dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final active = _entry(
        id: 'a1',
        type: SlaRuleType.maxToleranceDelay,
        config: {'threshold_minutes': 15},
        version: 2,
        isActive: true,
      );

      await tester.pumpWidget(
        _host(
          active: {SlaRuleType.maxToleranceDelay: active},
          history: [active],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Agendar'));
      await tester.pumpAndSettle();

      expect(find.text('Vigência a partir de'), findsOneWidget);
      expect(find.text('Tolerância de atraso (min)'), findsOneWidget);
    });
  });
}
