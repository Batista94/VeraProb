import 'dart:typed_data';

import 'package:veraprob/application/dispute_portal/i_file_hasher.dart';

class FakeFileHasher implements IFileHasher {
  String? overrideHex;
  bool shouldThrow = false;

  @override
  Future<String> sha256Hex(Uint8List bytes) async {
    if (shouldThrow) {
      throw const HasherException('Simulated hasher error');
    }
    if (overrideHex != null) {
      return overrideHex!;
    }
    // Determinist fallback for testing
    return 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  }
}
