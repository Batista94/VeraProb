// governance_audit_screen_test.dart
//
// Comportamento da aba "Histórico" (Settings Hub):
// - Estado vazio / erro / carregando com mensagens sem exceção crua (UX-RAW-EXCEPTION).
// - Renderização de eventos com rótulo PT-BR mapeado por tipo de evento.
// - Filtro de e-mail (cliente) reduz a lista sem nova chamada ao provider.
// - Filtro de categoria troca a chave da família do provider.
// - Tap em uma linha abre o diálogo de detalhe com o provenance completo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/admin/governance_audit_query_service.dart';
import 'package:veraprob/features/admin/presentation/screens/governance_audit_screen.dart';
import 'package:veraprob/state/providers/admin_providers.dart';

GovernanceAuditEntry _entry({
  required String eventType,
  String? actorEmail = 'admin@empresa.com',
  String? targetEmail = 'membro@empresa.com',
  String? reason,
  DateTime? occurredAtUtc,
}) {
  return GovernanceAuditEntry(
    // Default period filter is "Últimos 30 dias" — keep fixtures fresh so
    // they aren't silently dropped by the client-side period cutoff.
    occurredAtUtc:
        occurredAtUtc ??
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    eventType: eventType,
    actorId: 'actor-1',
    actorEmail: actorEmail,
    targetUserId: 'target-1',
    targetEmail: targetEmail,
    reason: reason,
  );
}

Widget _wrap({
  required List<GovernanceAuditEntry> Function(GovernanceEventCategory?)
  entriesFor,
}) {
  return ProviderScope(
    overrides: [
      governanceAuditLogProvider.overrideWith(
        (ref, category) async => entriesFor(category),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: GovernanceAuditScreen())),
  );
}

void main() {
  testWidgets('lista vazia mostra mensagem sem exceção', (tester) async {
    await tester.pumpWidget(_wrap(entriesFor: (_) => const []));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Nenhum evento de governança encontrado para os filtros selecionados.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('erro no provider mostra mensagem amigável, nunca o erro cru', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          governanceAuditLogProvider.overrideWith(
            (ref, category) async =>
                throw StateError('boom: raw infra failure'),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: GovernanceAuditScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Não foi possível carregar o histórico de governança. Tente novamente.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('eventos renderizam com rótulo PT-BR mapeado', (tester) async {
    await tester.pumpWidget(
      _wrap(
        entriesFor: (_) => [
          _entry(eventType: 'MEMBER_DEACTIVATED'),
          _entry(eventType: 'ROLE_ASSIGNED', targetEmail: null),
          _entry(eventType: 'SOME_UNMAPPED_EVENT'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Membro inativado'), findsOneWidget);
    expect(find.text('Perfil atribuído'), findsOneWidget);
    // Unknown event types fall back to the raw type rather than disappearing.
    expect(find.text('SOME_UNMAPPED_EVENT'), findsOneWidget);
  });

  testWidgets('filtro de e-mail reduz a lista no cliente', (tester) async {
    await tester.pumpWidget(
      _wrap(
        entriesFor: (_) => [
          _entry(eventType: 'MEMBER_INVITED', targetEmail: 'ana@empresa.com'),
          _entry(eventType: 'MEMBER_REMOVED', targetEmail: 'bruno@empresa.com'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Convite enviado'), findsOneWidget);
    expect(find.text('Membro removido'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Filtrar por e-mail (ator ou alvo)'),
      'ana@',
    );
    await tester.pumpAndSettle();

    expect(find.text('Convite enviado'), findsOneWidget);
    expect(find.text('Membro removido'), findsNothing);
  });

  testWidgets('trocar a categoria consulta a família do provider correta', (
    tester,
  ) async {
    final requestedCategories = <GovernanceEventCategory?>[];
    await tester.pumpWidget(
      _wrap(
        entriesFor: (category) {
          requestedCategories.add(category);
          return const [];
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(requestedCategories, contains(null));

    await tester.tap(
      find.byType(DropdownButtonFormField<GovernanceEventCategory?>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Membros').last);
    await tester.pumpAndSettle();

    expect(requestedCategories, contains(GovernanceEventCategory.members));
  });

  testWidgets('tap em um evento abre o diálogo de detalhe com provenance', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        entriesFor: (_) => [
          _entry(
            eventType: 'MEMBER_REMOVED',
            actorEmail: 'admin@empresa.com',
            targetEmail: 'saiu@empresa.com',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Membro removido'));
    await tester.pumpAndSettle();

    expect(find.text('QUANDO'), findsOneWidget);
    expect(find.text('admin@empresa.com'), findsOneWidget);
    expect(find.text('saiu@empresa.com'), findsOneWidget);

    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('QUANDO'), findsNothing);
  });
}
