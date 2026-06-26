// Forensic Audit Signature: TEST-JSF-v1.0 / QA-Integrity
// Security Guard: INV-24 Compliance Verified
// Coverage: Hashing / Audit-Checklist / Upload / Validation / Multi-tenant
//
// NOTE — scenarios that require `_pickFiles()` (file-picker browser API) are
// covered by injecting files via the mocked [JustificationFileService].
// Scenarios requiring `dart:js_interop` at runtime (actual HTML input) are
// excluded from VM tests by design (INV-17).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'package:veraprob/application/sla_audit/justification/submit_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_submission_token.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/file_service/justification_file_service.dart';
import 'package:veraprob/features/admin/presentation/screens/justification_submission_form.dart';
import 'package:veraprob/presentation/shared/ui/evidence_validation_checklist_widget.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/justification_providers.dart';

// ── Mocks / Fakes ─────────────────────────────────────────────────────────────

class _MockSubmitHandler extends Mock implements SubmitJustificationHandler {}

class _MockStorageService extends Mock
    implements JustificationEvidenceStorageService {}

class _MockFileService extends Mock implements JustificationFileService {}

class _FakeSubmitCommand extends Fake implements SubmitJustificationCommand {}

// ── Constants ─────────────────────────────────────────────────────────────────

const _kOrgId = 'org-forensic-001';
const _kUserId = 'user-auditor-001';
const _kSessionId = 'session-tok-abc123';
const _kContractId = 'contract-test-999';
const _kSetId = 'set-test-abc';
const _kValidDesc = 'Falha mecânica confirmada no motor do veículo SL-903';

// ── Fixtures ──────────────────────────────────────────────────────────────────

ContractorJustification _fakeJustification() => ContractorJustification(
  id: 'j-001',
  organizationId: _kOrgId,
  contractId: _kContractId,
  setId: _kSetId,
  submittedByToken: null,
  category: JustificationCategory.mechanical,
  description: _kValidDesc,
  status: JustificationStatus.pending,
  reviewedByUserId: null,
  reviewedAtUtc: null,
  createdAtUtc: DateTime.utc(2026, 4, 20),
);

JustificationSubmissionToken _fakeToken() => JustificationSubmissionToken(
  id: 'token-id-001',
  organizationId: _kOrgId,
  contractId: _kContractId,
  setId: _kSetId,
  justificationId: null,
  token: 'tok-abc-123',
  createdByUserId: _kUserId,
  expiresAtUtc: DateTime.utc(2026, 4, 21),
  usedAtUtc: null,
  createdAtUtc: DateTime.utc(2026, 4, 20),
);

// ── Widget builder ────────────────────────────────────────────────────────────

Widget _buildForm({
  String? contractId,
  String? setId,
  JustificationSubmissionToken? token,
  required _MockSubmitHandler handler,
  _MockStorageService? storage,
  _MockFileService? fileService,
  String? orgId = _kOrgId,
  String? userId = _kUserId,
  UserRole role = UserRole.auditor,
  String? sessionId = _kSessionId,
}) {
  return ProviderScope(
    overrides: [
      currentOrganizationIdProvider.overrideWithValue(orgId),
      currentOperatorIdProvider.overrideWithValue(userId),
      currentUserRoleProvider.overrideWithValue(role),
      currentSessionIdProvider.overrideWithValue(sessionId),
      authStateProvider.overrideWith((ref) => const Stream<AuthState>.empty()),
      submitJustificationHandlerProvider.overrideWithValue(handler),
      justificationStorageServiceProvider.overrideWithValue(
        storage ?? _MockStorageService(),
      ),
      justificationFileServiceProvider.overrideWithValue(
        fileService ?? _MockFileService(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: JustificationSubmissionForm(
          contractId: contractId,
          setId: setId,
          token: token,
        ),
      ),
    ),
  );
}

void _setSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
}

/// Fills operator path TextFormFields using index order:
/// [0] = ID do Contrato, [1] = SET ID, [2] = Descrição
Future<void> _fillOperatorForm(
  WidgetTester tester, {
  String contractId = _kContractId,
  String setId = _kSetId,
  String description = _kValidDesc,
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), contractId);
  await tester.enterText(fields.at(1), setId);
  await tester.enterText(fields.at(2), description);
}

/// Injects [files] into the form's internal `_files` list by simulating the
/// pick-files callback via [_MockFileService].
void _stubPickFiles(
  _MockFileService service,
  List<({String name, Uint8List bytes})> files,
) {
  when(
    () => service.pickFiles(),
  ).thenAnswer((_) async => PickedFilesResult(picked: files, oversized: []));
}

void _stubPickFilesWithOversized(
  _MockFileService service,
  List<({String name, Uint8List bytes})> picked,
  List<String> oversized,
) {
  when(() => service.pickFiles()).thenAnswer(
    (_) async => PickedFilesResult(picked: picked, oversized: oversized),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// main
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSubmitCommand());
    registerFallbackValue(Uint8List(0));
  });

  // ── Group 1: SHA-256 Integrity (INV-9 / AUDITOR / SENIOR) ─────────────────
  group('SHA-256 Forensic Hash — Integridade (INV-9)', () {
    test('hash of "VeraProb_Secret_Data" is 64 hex chars', () {
      final bytes = utf8.encode('VeraProb_Secret_Data');
      final hash = sha256.convert(bytes).toString();
      expect(hash.length, 64);
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('hash deterministic on same bytes (INV-15)', () {
      final bytes = Uint8List.fromList(utf8.encode('VeraProb_Secret_Data'));
      final h1 = sha256.convert(bytes).toString();
      final h2 = sha256.convert(bytes).toString();
      expect(h1, h2);
    });

    test('widget-side hash == independent pericial recomputation', () {
      // Mirror of _pickFiles: sha256.convert(f.bytes).toString()
      const content = 'VeraProb_Secret_Data';
      final bytes = Uint8List.fromList(utf8.encode(content));

      final widgetSideHash = sha256.convert(bytes).toString();

      // Independent re-computation (pericial reference)
      final pericialBytes = List<int>.unmodifiable(utf8.encode(content));
      final pericialHash = sha256.convert(pericialBytes).toString();

      expect(widgetSideHash, pericialHash);
    });

    test(
      'distinct file bytes yield distinct hashes (collision resistance)',
      () {
        final h1 = sha256.convert(utf8.encode('file-A-content')).toString();
        final h2 = sha256.convert(utf8.encode('file-B-content')).toString();
        expect(h1, isNot(h2));
      },
    );

    test('file size limit constant equals 10 MB', () {
      expect(JustificationFileService.maxFileSizeBytes, 10 * 1024 * 1024);
    });
  });

  // ── Group 2: Token Path — ReadOnly fields (ARCHITECT) ─────────────────────
  group('Token Path — Campos somente-leitura (ARCHITECT)', () {
    testWidgets('contractId e setId do token renderizados em ReadOnly', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      final token = _fakeToken();

      await tester.pumpWidget(_buildForm(handler: handler, token: token));
      await tester.pumpAndSettle();

      expect(find.text(token.contractId), findsOneWidget);
      expect(find.text(token.setId), findsOneWidget);
      expect(find.text('CONTRATO'), findsOneWidget);
    });

    testWidgets(
      'modo token: ausência de TextFormField para IDs (inalterável)',
      (tester) async {
        _setSize(tester);
        final handler = _MockSubmitHandler();

        await tester.pumpWidget(
          _buildForm(handler: handler, token: _fakeToken()),
        );
        await tester.pumpAndSettle();

        // Only description TextFormField present; contract/setId are ReadOnly
        expect(find.byType(TextFormField), findsOneWidget);
      },
    );
  });

  // ── Group 3: Operator Path — Campos editáveis ─────────────────────────────
  group('Operator Path — Campos editáveis', () {
    testWidgets('campos ID Contrato, SET ID e Descrição presentes', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.text('Nova Justificativa'), findsOneWidget);
      expect(find.text('Enviar Justificativa'), findsOneWidget);
    });

    testWidgets('botão Enviar habilitado no estado inicial', (tester) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNotNull);
    });
  });

  // ── Group 4: Validação de Formulário — Regra de Negócio (MAVERICK) ─────────
  group('Validação — Regra de Negócio (MAVERICK)', () {
    testWidgets('descrição < 20 chars bloqueia envio', (tester) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), _kContractId);
      await tester.enterText(fields.at(1), _kSetId);
      await tester.enterText(fields.at(2), 'curto'); // < 20 chars

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(
        find.text('A descrição deve ter pelo menos 20 caracteres.'),
        findsOneWidget,
      );
      verifyNever(() => handler.handle(any()));
    });

    testWidgets('contractId vazio bloqueia envio com mensagem "Obrigatório"', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      // Leave contractId (at(0)) empty
      await tester.enterText(fields.at(1), _kSetId);
      await tester.enterText(fields.at(2), _kValidDesc);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Obrigatório'), findsWidgets);
      verifyNever(() => handler.handle(any()));
    });

    testWidgets('setId vazio bloqueia envio com mensagem "Obrigatório"', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), _kContractId);
      // Leave setId (at(1)) empty
      await tester.enterText(fields.at(2), _kValidDesc);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Obrigatório'), findsOneWidget);
      verifyNever(() => handler.handle(any()));
    });
  });

  // ── Group 5: Multi-tenant Identity (INV-1 / ARCHITECT) ────────────────────
  group('Multi-tenant — INV-1 (ARCHITECT)', () {
    testWidgets(
      'organization_id do JWT injetado no SubmitJustificationCommand',
      (tester) async {
        _setSize(tester);
        final handler = _MockSubmitHandler();
        when(
          () => handler.handle(any()),
        ).thenAnswer((_) async => _fakeJustification());

        await tester.pumpWidget(_buildForm(handler: handler, orgId: _kOrgId));
        await tester.pumpAndSettle();

        await _fillOperatorForm(tester);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        final captured = verify(() => handler.handle(captureAny())).captured;
        final cmd = captured.single as SubmitJustificationCommand;
        expect(cmd.organizationId, _kOrgId);
      },
    );

    testWidgets('org_id nulo mostra erro, handler nunca chamado', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler, orgId: null));
      await tester.pumpAndSettle();

      await _fillOperatorForm(tester);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('Organização não encontrada.'), findsOneWidget);
      verifyNever(() => handler.handle(any()));
    });

    testWidgets('comando carrega contractId, setId e description corretos', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      when(
        () => handler.handle(any()),
      ).thenAnswer((_) async => _fakeJustification());

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      await _fillOperatorForm(tester);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final captured = verify(() => handler.handle(captureAny())).captured;
      final cmd = captured.single as SubmitJustificationCommand;
      expect(cmd.contractId, _kContractId);
      expect(cmd.setId, _kSetId);
      expect(cmd.description, _kValidDesc);
      expect(cmd.callerRole, UserRole.auditor); // Operator path sets callerRole
      expect(cmd.submittedByTokenId, isNull); // Not a token path
    });
  });

  // ── Group 6: Token Path Submit (ARCHITECT) ─────────────────────────────────
  group('Token Path Submit (ARCHITECT)', () {
    testWidgets(
      'token path: callerRole null, submittedByTokenId preenchido (INV-1)',
      (tester) async {
        _setSize(tester);
        final handler = _MockSubmitHandler();
        when(
          () => handler.handle(any()),
        ).thenAnswer((_) async => _fakeJustification());
        final token = _fakeToken();

        await tester.pumpWidget(_buildForm(handler: handler, token: token));
        await tester.pumpAndSettle();

        // Only description field in token mode
        await tester.enterText(find.byType(TextFormField).first, _kValidDesc);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        final captured = verify(() => handler.handle(captureAny())).captured;
        final cmd = captured.single as SubmitJustificationCommand;
        expect(cmd.contractId, token.contractId);
        expect(cmd.setId, token.setId);
        expect(cmd.organizationId, _kOrgId);
        expect(cmd.submittedByTokenId, token.id);
        expect(cmd.callerRole, isNull); // Token path bypasses RBAC
      },
    );
  });

  // ── Group 7: Sucesso com Evidências (AUDITOR / INV-9) ──────────────────────
  group('Sucesso com Evidências — Hash Match (AUDITOR / INV-9)', () {
    testWidgets(
      'hashes SHA-256 dos arquivos injetados no SubmitJustificationCommand',
      (tester) async {
        _setSize(tester);
        final handler = _MockSubmitHandler();
        final storage = _MockStorageService();
        final fileService = _MockFileService();
        when(
          () => handler.handle(any()),
        ).thenAnswer((_) async => _fakeJustification());

        const contentA = 'VeraProb_Secret_Data';
        const contentB = 'forensic_evidence_file_b';
        final bytesA = Uint8List.fromList(utf8.encode(contentA));
        final bytesB = Uint8List.fromList(utf8.encode(contentB));
        final expectedHashA = sha256.convert(bytesA).toString();
        final expectedHashB = sha256.convert(bytesB).toString();

        _stubPickFiles(fileService, [
          (name: 'evidence_a.pdf', bytes: bytesA),
          (name: 'evidence_b.pdf', bytes: bytesB),
        ]);

        // Storage stubs for authenticated upload path
        when(
          () => storage.uploadAuthenticated(
            organizationId: any(named: 'organizationId'),
            justificationId: any(named: 'justificationId'),
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
          ),
        ).thenAnswer((inv) async {
          final name = inv.namedArguments[const Symbol('fileName')] as String;
          return '$_kOrgId/pending/$name';
        });
        when(() => storage.getScanUrl(any())).thenAnswer(
          (inv) async => 'https://scan/${inv.positionalArguments[0]}',
        );

        await tester.pumpWidget(
          _buildForm(
            handler: handler,
            storage: storage,
            fileService: fileService,
          ),
        );
        await tester.pumpAndSettle();

        await _fillOperatorForm(tester);

        // Trigger file picker via "Anexar Arquivo"
        await tester.tap(find.text('Anexar Arquivo'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        final captured = verify(() => handler.handle(captureAny())).captured;
        final cmd = captured.single as SubmitJustificationCommand;

        // INV-9: hashes must match independent SHA-256 computation
        expect(cmd.evidenceHashes, hasLength(2));
        expect(cmd.evidenceHashes[0], expectedHashA);
        expect(cmd.evidenceHashes[1], expectedHashB);
      },
    );
  });

  // ── Group 8: Falha de Upload — Resiliência (QA / SENIOR) ──────────────────
  group('Resiliência — Falha de Upload 500 (QA / SENIOR)', () {
    testWidgets(
      'uploadPut lança exceção → step transfer "failed" + botão re-habilitado',
      (tester) async {
        _setSize(tester);
        final handler = _MockSubmitHandler();
        final storage = _MockStorageService();
        final fileService = _MockFileService();

        final bytes = Uint8List.fromList(utf8.encode('evidence content'));
        _stubPickFiles(fileService, [(name: 'doc.pdf', bytes: bytes)]);

        // Token path so upload goes via signed URL
        final token = _fakeToken();
        when(
          () => storage.getSignedUploadUrl(
            justificationToken: any(named: 'justificationToken'),
            fileName: any(named: 'fileName'),
          ),
        ).thenAnswer(
          (_) async =>
              (url: 'https://signed/upload', storagePath: 'org/j/doc.pdf'),
        );

        // Simulate HTTP 500 from upload
        when(
          () => fileService.uploadPut(any(), any()),
        ).thenThrow(Exception('Falha no upload do arquivo (500).'));

        await tester.pumpWidget(
          _buildForm(
            handler: handler,
            storage: storage,
            fileService: fileService,
            token: token,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, _kValidDesc);
        await tester.tap(find.text('Anexar Arquivo'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        // Step "transfer" must be failed
        final stepWidget = tester.widget<EvidenceValidationChecklistWidget>(
          find.byType(EvidenceValidationChecklistWidget),
        );
        final transferStep = stepWidget.steps.firstWhere(
          (s) => s.kind == EvidenceValidationStepKind.transfer,
        );
        expect(transferStep.status, EvidenceValidationStatus.failed);

        // Submit button re-enabled after failure (resilience)
        final btn = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(btn.onPressed, isNotNull);

        // Handler was never called (upload failed before handler)
        verifyNever(() => handler.handle(any()));
      },
    );
  });

  // ── Group 9: Fail-Fast >10MB (BREAKER / QA) ───────────────────────────────
  group('Fail-Fast — Arquivo > 10 MB (BREAKER)', () {
    testWidgets('arquivo oversized: SnackBar de erro, _files permanece vazia', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      final fileService = _MockFileService();

      // Service returns oversized filename without bytes
      _stubPickFilesWithOversized(
        fileService,
        [], // no successfully picked files
        ['evidence_large.zip'], // oversized
      );

      await tester.pumpWidget(
        _buildForm(handler: handler, fileService: fileService),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Anexar Arquivo'));
      await tester.pumpAndSettle();

      // SnackBar with error about oversized file
      expect(find.textContaining('evidence_large.zip'), findsOneWidget);
      expect(find.textContaining('10 MB'), findsWidgets);

      // No file added to the list
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
    });
  });

  // ── Group 10: Fluxo de Envio (SENIOR / QA) ────────────────────────────────
  group('Fluxo de Envio (SENIOR / QA)', () {
    testWidgets('sucesso: SnackBar "Justificativa enviada com sucesso"', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      when(
        () => handler.handle(any()),
      ).thenAnswer((_) async => _fakeJustification());

      // Use dialog wrapper so Navigator.pop() dismisses the form and
      // ScaffoldMessenger on the outer scaffold can host the snackbar
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentOrganizationIdProvider.overrideWithValue(_kOrgId),
            currentOperatorIdProvider.overrideWithValue(_kUserId),
            currentUserRoleProvider.overrideWithValue(UserRole.auditor),
            currentSessionIdProvider.overrideWithValue(_kSessionId),
            authStateProvider.overrideWith(
              (ref) => const Stream<AuthState>.empty(),
            ),
            submitJustificationHandlerProvider.overrideWithValue(handler),
            justificationStorageServiceProvider.overrideWithValue(
              _MockStorageService(),
            ),
            justificationFileServiceProvider.overrideWithValue(
              _MockFileService(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: ctx,
                    builder: (_) => const JustificationSubmissionForm(
                      contractId: _kContractId,
                      setId: _kSetId,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await _fillOperatorForm(tester);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('Justificativa enviada com sucesso.'), findsOneWidget);
    });

    testWidgets(
      'erro do handler: texto de erro visível + botão re-habilitado',
      (tester) async {
        _setSize(tester);
        final handler = _MockSubmitHandler();
        when(
          () => handler.handle(any()),
        ).thenAnswer((_) => Future.error(Exception('Upload falhou: 500')));

        await tester.pumpWidget(_buildForm(handler: handler));
        await tester.pumpAndSettle();

        await _fillOperatorForm(tester);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(find.textContaining('Falha ao enviar justificativa. Tente novamente.'), findsOneWidget);

        final btn = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(btn.onPressed, isNotNull);
      },
    );

    testWidgets('estado de carregamento: spinner visível, botão desabilitado', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      final completer = Completer<ContractorJustification>();
      when(() => handler.handle(any())).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      await _fillOperatorForm(tester);
      await tester.tap(find.byType(FilledButton));
      await tester.pump(); // Do NOT settle — keep in loading state

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);

      // Complete to avoid test leak
      completer.complete(_fakeJustification());
      await tester.pumpAndSettle();
    });
  });

  // ── Group 11: UX Forense — Checklist (UX/OPS) ────────────────────────────
  group('UX Forense — Checklist de Auditoria (UX/OPS)', () {
    testWidgets('EvidenceValidationChecklistWidget ausente antes do envio', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      expect(find.byType(EvidenceValidationChecklistWidget), findsNothing);
      expect(find.text('VALIDAÇÃO FORENSE'), findsNothing);
    });

    testWidgets(
      'checklist aparece durante envio com arquivos (estados running/completed)',
      (tester) async {
        _setSize(tester);
        final handler = _MockSubmitHandler();
        final storage = _MockStorageService();
        final fileService = _MockFileService();
        final completer = Completer<ContractorJustification>();
        when(() => handler.handle(any())).thenAnswer((_) => completer.future);

        final bytes = Uint8List.fromList(utf8.encode('evidence'));
        _stubPickFiles(fileService, [(name: 'file.pdf', bytes: bytes)]);
        when(
          () => storage.uploadAuthenticated(
            organizationId: any(named: 'organizationId'),
            justificationId: any(named: 'justificationId'),
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
          ),
        ).thenAnswer((_) async => 'org/j/file.pdf');
        when(
          () => storage.getScanUrl(any()),
        ).thenAnswer((_) async => 'https://scan/file.pdf');

        await tester.pumpWidget(
          _buildForm(
            handler: handler,
            storage: storage,
            fileService: fileService,
          ),
        );
        await tester.pumpAndSettle();

        await _fillOperatorForm(tester);
        await tester.tap(find.text('Anexar Arquivo'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FilledButton));
        await tester.pump(); // Start submit, keep loading

        expect(find.byType(EvidenceValidationChecklistWidget), findsOneWidget);

        // digitalIdentity step is marked completed immediately (hash sealed)
        final stepWidget = tester.widget<EvidenceValidationChecklistWidget>(
          find.byType(EvidenceValidationChecklistWidget),
        );
        final idStep = stepWidget.steps.firstWhere(
          (s) => s.kind == EvidenceValidationStepKind.digitalIdentity,
        );
        expect(idStep.status, EvidenceValidationStatus.completed);

        completer.complete(_fakeJustification());
        await tester.pumpAndSettle();
      },
    );
  });

  // ── Group 12: Seção de Evidências — UI (BREAKER / QA) ─────────────────────
  group('Seção de Evidências — UI (BREAKER)', () {
    testWidgets('"Anexar Arquivo" button presente', (tester) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      expect(find.text('Anexar Arquivo'), findsOneWidget);
    });

    testWidgets('caption de tamanho máximo presente', (tester) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();

      await tester.pumpWidget(_buildForm(handler: handler));
      await tester.pumpAndSettle();

      expect(
        find.text('Máx. 10 MB por arquivo. Imagens, PDF ou ZIP.'),
        findsOneWidget,
      );
    });

    testWidgets('arquivo adicionado via picker aparece na lista', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      final fileService = _MockFileService();

      final bytes = Uint8List.fromList(utf8.encode('content'));
      _stubPickFiles(fileService, [(name: 'receipt.pdf', bytes: bytes)]);

      await tester.pumpWidget(
        _buildForm(handler: handler, fileService: fileService),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Anexar Arquivo'));
      await tester.pumpAndSettle();

      expect(find.text('receipt.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    });

    testWidgets('botão remover arquivo limpa item da lista', (tester) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      final fileService = _MockFileService();

      final bytes = Uint8List.fromList(utf8.encode('content'));
      _stubPickFiles(fileService, [(name: 'receipt.pdf', bytes: bytes)]);

      await tester.pumpWidget(
        _buildForm(handler: handler, fileService: fileService),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Anexar Arquivo'));
      await tester.pumpAndSettle();

      expect(find.text('receipt.pdf'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      expect(find.text('receipt.pdf'), findsNothing);
    });
  });
}
