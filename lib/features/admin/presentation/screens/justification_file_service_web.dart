import 'dart:js_interop';
import 'dart:typed_data';

import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:web/web.dart' as web;

import 'justification_file_service_interface.dart';

// ignore: non_constant_identifier_names
JustificationFileService createJustificationFileService() => _WebFileService();

class _WebFileService implements JustificationFileService {
  @override
  Future<PickedFilesResult> pickFiles() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/*,.pdf,.zip'
      ..multiple = true;

    input.click();
    await input.onChange.first;

    final fileList = input.files;
    if (fileList == null) {
      return const PickedFilesResult(picked: [], oversized: []);
    }

    final picked = <PickedFile>[];
    final oversized = <String>[];

    for (var i = 0; i < fileList.length; i++) {
      final file = fileList.item(i);
      if (file == null) continue;
      if (file.size > JustificationFileService.maxFileSizeBytes) {
        oversized.add(file.name);
        continue;
      }
      final bytes = await _readBytes(file);
      picked.add((name: file.name, bytes: bytes));
    }

    return PickedFilesResult(picked: picked, oversized: oversized);
  }

  Future<Uint8List> _readBytes(web.File file) async {
    final reader = web.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoadEnd.first;
    final result = reader.result;
    if (result == null) return Uint8List(0);
    return Uint8List.view((result as JSArrayBuffer).toDart);
  }

  @override
  Future<void> uploadPut(String url, Uint8List bytes) async {
    final response = await web.window
        .fetch(url.toJS, web.RequestInit(method: 'PUT', body: bytes.toJS))
        .toDart;
    if (!response.ok) {
      throw DomainException(
        'Falha no upload do arquivo (${response.status}). Tente novamente.',
      );
    }
  }
}
