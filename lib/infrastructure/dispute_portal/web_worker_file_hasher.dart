import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:veraprob/application/dispute_portal/i_file_hasher.dart';

@JS()
extension type _WorkerResult._(JSObject _) implements JSObject {
  external JSBoolean get success;
  external JSString? get hash;
  external JSString? get error;
}

class WebWorkerFileHasher implements IFileHasher {
  const WebWorkerFileHasher();

  @override
  Future<String> sha256Hex(Uint8List bytes) async {
    final completer = Completer<String>();

    try {
      final worker = web.Worker('sha256_worker.js'.toJS);

      // Clone bytes to prevent the original ArrayBuffer from becoming detached
      // after transferring it to the worker. If detached, subsequent API calls fail.
      final clone = Uint8List.fromList(bytes);

      worker.onmessage = ((web.MessageEvent event) {
        final data = event.data as _WorkerResult;

        if (data.success.toDart) {
          completer.complete(data.hash!.toDart);
        } else {
          final errorMsg = data.error?.toDart ?? 'Erro desconhecido no Worker';
          completer.completeError(HasherException(errorMsg));
        }

        worker.terminate();
      }).toJS;

      worker.onerror = ((web.Event event) {
        completer.completeError(
          const HasherException('Erro fatal de execução no Web Worker.'),
        );
        worker.terminate();
      }).toJS;

      // Transfer the buffer ownership to the worker to avoid structural clone cost
      final jsBuffer = clone.buffer.toJS;
      worker.postMessage(jsBuffer, [jsBuffer].toJS);
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(
          HasherException('Falha ao inicializar o Web Worker: $e'),
        );
      }
    }

    return completer.future;
  }
}
