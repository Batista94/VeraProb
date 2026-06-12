import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/features/admin/presentation/widgets/dispute_evidence_upload_panel.dart';
import 'package:veraprob/state/providers/dispute_evidence_providers.dart';

const _queueEntryId = 'queue-001';

DisputeEvidenceAttachment _attachment({
  required String id,
  required String fileName,
  required int sizeBytes,
  EvidenceVerificationStatus status = EvidenceVerificationStatus.pending,
}) {
  return DisputeEvidenceAttachment(
    id: id,
    organizationId: 'org-001',
    queueEntryId: _queueEntryId,
    storagePath: 'org-001/$_queueEntryId/$id',
    fileName: fileName,
    mimeType: 'image/png',
    fileSizeBytes: sizeBytes,
    sha256Hash: 'a' * 64,
    verificationStatus: status,
    hashVerifiedAtUtc: null,
    uploadedBy: 'user-1',
    attachedAtUtc: DateTime.utc(2026, 1, 15, 12, 0),
    deletedAtUtc: null,
  );
}

Widget _host(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DisputeEvidenceUploadPanel(queueEntryId: _queueEntryId),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('empty list shows 0/10 and empty message', (tester) async {
    await tester.pumpWidget(
      _host([
        disputeEvidenceListProvider.overrideWith(
          (ref, key) async => const <DisputeEvidenceAttachment>[],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('0/10'), findsOneWidget);
    expect(find.text('Nenhuma evidência anexada.'), findsOneWidget);
    expect(find.text('Anexar evidência'), findsOneWidget);
  });

  testWidgets('renders chips with file name + human size (not UUID)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        disputeEvidenceListProvider.overrideWith(
          (ref, key) async => [
            _attachment(
              id: 'uuid-aaaa',
              fileName: 'laudo.png',
              sizeBytes: 2048,
              status: EvidenceVerificationStatus.verified,
            ),
            _attachment(
              id: 'uuid-bbbb',
              fileName: 'foto.png',
              sizeBytes: 3145728,
            ),
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('2/10'), findsOneWidget);
    expect(find.text('laudo.png'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    expect(find.text('foto.png'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
    // UUID never surfaced to the user.
    expect(find.textContaining('uuid-'), findsNothing);
  });

  testWidgets('at limit disables add button', (tester) async {
    await tester.pumpWidget(
      _host([
        disputeEvidenceListProvider.overrideWith(
          (ref, key) async => List.generate(
            10,
            (i) => _attachment(
              id: 'uuid-$i',
              fileName: 'f$i.png',
              sizeBytes: 1024,
            ),
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('10/10'), findsOneWidget);
    expect(find.text('Limite de 10 anexos atingido'), findsOneWidget);

    final btn = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('dispute-evidence-add-button')),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('remove icon opens confirm dialog; CANCELAR dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        disputeEvidenceListProvider.overrideWith(
          (ref, key) async => [
            _attachment(id: 'uuid-x', fileName: 'doc.png', sizeBytes: 1024),
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('evidence-remove-uuid-x')));
    await tester.pumpAndSettle();

    expect(find.text('Remover evidência?'), findsOneWidget);

    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();

    expect(find.text('Remover evidência?'), findsNothing);
  });
}
