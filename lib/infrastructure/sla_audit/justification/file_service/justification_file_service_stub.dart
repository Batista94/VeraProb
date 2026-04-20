import 'dart:typed_data';

import 'justification_file_service_interface.dart';

// ignore: non_constant_identifier_names
JustificationFileService createJustificationFileService() => _StubFileService();

class _StubFileService implements JustificationFileService {
  @override
  Future<PickedFilesResult> pickFiles() =>
      throw UnsupportedError('File picking not supported on this platform.');

  @override
  Future<void> uploadPut(String url, Uint8List bytes) =>
      throw UnsupportedError('Upload not supported on this platform.');
}
