// dirty_level_a.dart
// ⚠️ TEST FIXTURE — DO NOT COMMIT TO REAL CODE
// This file contains fake secrets to validate the Forensic Secrets Scanner.
// Expected: Scanner blocks this file (Level A — Regex match)

class FakeSupabaseConfig {
  // Fake Supabase key — scanner must detect sbp_ pattern
  static const String serviceRoleKey =
      'sbp_FakeKeyForTestingPurposesOnly12345678901';

  // Fake GitHub PAT — scanner must detect ghp_ pattern
  static const String githubToken =
      'ghp_FakeGitHubTokenForTestingPurposes123456';

  // Fake generic API key — scanner must detect key= pattern
  static const String apiKey = 'api_key = "fakesecretkey_1234567890abcdef"';
}
