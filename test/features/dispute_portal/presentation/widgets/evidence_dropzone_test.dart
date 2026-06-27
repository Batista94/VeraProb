import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_submission_notifier.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';
import 'package:veraprob/features/dispute_portal/presentation/widgets/evidence_dropzone.dart';

// NOTE: Scenarios that require _pickFile() (file-picker browser API) cannot be
// triggered in widget tests without platform-channel mocking. The
// UX-RAW-EXCEPTION guard (_humanizeFilePickError) is enforced by code review.
// Tests here cover widget state display paths accessible via the `state` param.

void main() {
  Widget buildDropzone({
    PortalSubmissionState state = const PortalSubmissionInitial(),
    void Function(StagedFile)? onFileStaged,
    VoidCallback? onFileCleared,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: EvidenceDropzone(
          state: state,
          onFileStaged: onFileStaged ?? (_) {},
          onFileCleared: onFileCleared ?? () {},
        ),
      ),
    );
  }

  StagedFile fakeFile({String name = 'prova.pdf'}) {
    return StagedFile(
      name: name,
      sizeBytes: 102400,
      mimeType: 'application/pdf',
      bytes: Uint8List(0),
    );
  }

  testWidgets('idle state shows upload zone with labels', (tester) async {
    await tester.pumpWidget(buildDropzone());

    expect(find.text('Toque para anexar evidência (máx 10MB)'), findsOneWidget);
    expect(find.text('Formatos: PDF, PNG, JPG'), findsOneWidget);
    expect(find.byIcon(Icons.upload_file), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('staging with file shows file name and clear button', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildDropzone(
        state: PortalSubmissionStaging(justification: '', file: fakeFile()),
      ),
    );

    expect(find.text('prova.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('staging without file still shows upload zone', (tester) async {
    await tester.pumpWidget(
      buildDropzone(state: const PortalSubmissionStaging(justification: '')),
    );

    expect(find.text('Toque para anexar evidência (máx 10MB)'), findsOneWidget);
  });

  testWidgets('hashing state disables tap and hides clear button', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildDropzone(state: const PortalSubmissionHashing()),
    );

    expect(find.byIcon(Icons.close), findsNothing);
    final inkWell = tester.widget<InkWell>(find.byType(InkWell).first);
    expect(inkWell.onTap, isNull);
  });
}
