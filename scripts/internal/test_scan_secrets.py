#!/usr/bin/env python3
"""
Validation test for scan_secrets.py — tests all 3 detection levels in isolation.
Run: python scripts/test_scan_secrets.py
"""
import sys
import os
# Point to scripts/security where the core scanner lives
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'security'))

from scan_secrets import COMPILED_PATTERNS, find_high_entropy_strings, MAGIC_HEADERS, shannon_entropy, mask

PASS = "\033[0;32m  [PASS]\033[0m"
FAIL = "\033[0;31m  [FAIL]\033[0m"

errors = 0

# ── Level A: Regex ────────────────────────────────────────────────────────────
print("\n=== LEVEL A (Regex Precision) ===")

level_a_cases = [
    ("sbp_FakeKeyForTestingPurposesOnly12345678901", "Supabase Secret Key"),
    ("ghp_FakeGitHubTokenForTestingPurposes123456", "GitHub Personal Access Token"),
    ('api_key = "fakesecretkey_1234567890abcdef"', "Generic API Key"),
    ("AKIAFAKEAWSKEY1234ABCD", "AWS Access Key ID"),
    ("AIzaFakeGoogleKey1234567890123456789AB", "Google API Key"),
]

for candidate, expected_desc in level_a_cases:
    matched = False
    for pattern, desc in COMPILED_PATTERNS:
        m = pattern.search(candidate)
        if m:
            print(f"{PASS} [{desc}] -> masked: {mask(m.group(0))}")
            matched = True
            break
    if not matched:
        print(f"{FAIL} Expected to detect '{expected_desc}' in: {candidate[:30]}...")
        errors += 1

# ── Level B: Shannon Entropy ──────────────────────────────────────────────────
print("\n=== LEVEL B (Shannon Entropy) ===")

level_b_cases = [
    "aB3kX9mZqR7wNpLsVdYtCuEjHfGiOeI2",
    "Xk9mP2nQzRvL5wBtYdCsAuEjHfGiOeJ8Wn",
]

for s in level_b_cases:
    h = shannon_entropy(s)
    if h >= 4.5:
        print(f"{PASS} High entropy string detected (H={h:.2f}) -> masked: {mask(s)}")
    else:
        print(f"{FAIL} Expected entropy >= 4.5 for: {s[:20]}... (got {h:.2f})")
        errors += 1

# Negative case: low entropy string must NOT trigger
low_entropy = "aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
results = find_high_entropy_strings(low_entropy)
if not results:
    print(f"{PASS} Low entropy string correctly ignored.")
else:
    print(f"{FAIL} Low entropy string was falsely flagged.")
    errors += 1

# ── Level C: Magic Bytes ──────────────────────────────────────────────────────
print("\n=== LEVEL C (Magic Bytes / PEM Headers) ===")

level_c_cases = [
    "-----BEGIN RSA PRIVATE KEY-----",
    "-----BEGIN PRIVATE KEY-----",
    "-----BEGIN EC PRIVATE KEY-----",
    "-----BEGIN OPENSSH PRIVATE KEY-----",
]

for header in level_c_cases:
    found = any(h in header for h in MAGIC_HEADERS)
    if found:
        print(f"{PASS} PEM header detected -> masked: {mask(header, 20)}")
    else:
        print(f"{FAIL} PEM header NOT detected: {header}")
        errors += 1

# ── Summary ───────────────────────────────────────────────────────────────────
print(f"\n{'='*50}")
if errors == 0:
    print("\033[0;32m  ALL TESTS PASSED — 3 detection levels operational.\033[0m")
else:
    print(f"\033[0;31m  {errors} TEST(S) FAILED.\033[0m")
print(f"{'='*50}\n")

sys.exit(0 if errors == 0 else 1)
