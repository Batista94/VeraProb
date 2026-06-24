import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/infrastructure/dispute_portal/chunked_file_hasher.dart';

void main() {
  group('ChunkedFileHasher', () {
    late ChunkedFileHasher hasher;

    setUp(() {
      hasher = const ChunkedFileHasher();
    });

    test('computes correct hash for empty bytes (e3b0c442...)', () async {
      final bytes = Uint8List(0);
      final expected = sha256.convert(bytes).toString();

      final hash = await hasher.sha256Hex(bytes);

      expect(hash, expected);
      expect(
        hash,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('computes correct hash for small payload', () async {
      const text = 'VeraProb Test Payload - Forensic Hash Verification';
      final bytes = Uint8List.fromList(utf8.encode(text));
      final expected = sha256.convert(bytes).toString();

      final hash = await hasher.sha256Hex(bytes);

      expect(hash, expected);
    });

    test(
      'computes correct hash for payload > chunk size (e.g. 150KB)',
      () async {
        final bytes = Uint8List(150 * 1024);
        // Fill with some deterministic data
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = i % 256;
        }
        final expected = sha256.convert(bytes).toString();

        final hash = await hasher.sha256Hex(bytes);

        expect(hash, expected);
      },
    );
  });
}
