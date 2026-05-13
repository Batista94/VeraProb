import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/super_admin/mfa_challenge_result.dart';

void main() {
  group('MfaChallengeResult', () {
    test('carries challengeId and factorId', () {
      const r = MfaChallengeResult(challengeId: 'ch-1', factorId: 'f-1');
      expect(r.challengeId, 'ch-1');
      expect(r.factorId, 'f-1');
    });
  });
}
