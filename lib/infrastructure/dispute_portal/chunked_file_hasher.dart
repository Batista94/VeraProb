import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import 'package:veraprob/application/dispute_portal/i_file_hasher.dart';

class ChunkedFileHasher implements IFileHasher {
  static const int _chunkSize = 64 * 1024; // 64 KB chunks

  const ChunkedFileHasher();

  @override
  Future<String> sha256Hex(Uint8List bytes) async {
    try {
      if (bytes.isEmpty) {
        return sha256.convert(bytes).toString();
      }

      final output = AccumulatorSink<Digest>();
      final input = sha256.startChunkedConversion(output);

      for (var i = 0; i < bytes.length; i += _chunkSize) {
        final int end = (i + _chunkSize < bytes.length)
            ? i + _chunkSize
            : bytes.length;
        // Zero-copy slice using view
        final chunk = bytes.buffer.asUint8List(
          bytes.offsetInBytes + i,
          end - i,
        );
        input.add(chunk);

        // Yield to the event loop every chunk (anti-jank Wasm/Web)
        await Future<void>.delayed(Duration.zero);
      }

      input.close();
      output.close();

      return output.events.single.toString();
    } catch (e) {
      throw HasherException('Failed to compute hash: $e');
    }
  }
}
