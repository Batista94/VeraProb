import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';
import 'package:veraprob/features/admin/presentation/widgets/dispute_reason_code_dropdown.dart';
import 'package:veraprob/state/providers/dispute_reason_code_providers.dart';

const _catalogue = <DisputeReasonCode>[
  DisputeReasonCode(
    code: 'ROUTE_DEVIATION',
    category: 'OPERATIONAL',
    labelPt: 'Desvio de Rota',
    labelEn: 'Route Deviation',
    isActive: true,
  ),
  DisputeReasonCode(
    code: 'SENSOR_FAULT',
    category: 'TECHNICAL',
    labelPt: 'Falha de Sensor',
    labelEn: 'Sensor Fault',
    isActive: true,
  ),
];

Widget _host({
  required List<Override> overrides,
  String? selected,
  ValueChanged<String?>? onChanged,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: DisputeReasonCodeDropdown(
            selectedCode: selected,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('loading state renders skeleton', (tester) async {
    final completer = Completer<List<DisputeReasonCode>>();
    await tester.pumpWidget(
      _host(
        overrides: [
          disputeReasonCodesProvider.overrideWith((ref) => completer.future),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Carregando motivos…'), findsOneWidget);

    completer.complete(_catalogue);
    await tester.pumpAndSettle();
  });

  testWidgets('error state renders domain-language message', (tester) async {
    await tester.pumpWidget(
      _host(
        overrides: [
          disputeReasonCodesProvider.overrideWith(
            (ref) async => throw Exception('boom'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível carregar os motivos. Tente novamente.'),
      findsOneWidget,
    );
  });

  testWidgets('empty catalogue renders empty message', (tester) async {
    await tester.pumpWidget(
      _host(
        overrides: [
          disputeReasonCodesProvider.overrideWith(
            (ref) async => const <DisputeReasonCode>[],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nenhum motivo disponível no catálogo.'), findsOneWidget);
  });

  testWidgets('data renders grouped menu and emits code on select', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _host(
        overrides: [
          disputeReasonCodesProvider.overrideWith((ref) async => _catalogue),
        ],
        onChanged: (c) => picked = c,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('dispute-reason-code-dropdown')),
    );
    await tester.pumpAndSettle();

    // Section headers present (uppercased categories).
    expect(find.text('OPERACIONAL'), findsOneWidget);
    expect(find.text('TÉCNICO'), findsOneWidget);

    await tester.tap(find.text('Falha de Sensor').last);
    await tester.pumpAndSettle();

    expect(picked, 'SENSOR_FAULT');
  });
}
