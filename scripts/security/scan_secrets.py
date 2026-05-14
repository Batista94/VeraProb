#!/usr/bin/env python3
"""
=============================================================================
VeraProb — Forensic Secrets Scanner (INV-28)
=============================================================================
Detects secrets, credentials and high-entropy strings in git staged files.
Runs only on protected branches (main) or when a PR is open.

Usage:
  python scripts/scan_secrets.py
  python scripts/scan_secrets.py --force-bypass "justified reason here"

Exit codes:
  0 = clean (or bypassed)
  1 = secret detected -> commit blocked
=============================================================================
"""

import sys
import os
import re
import math
import subprocess
import datetime
import argparse

# ── ANSI Colors ───────────────────────────────────────────────────────────────
RED    = "\033[0;31m"
YELLOW = "\033[1;33m"
GREEN  = "\033[0;32m"
BOLD   = "\033[1m"
NC     = "\033[0m"

# ── Configuration ─────────────────────────────────────────────────────────────
TARGET_EXTENSIONS = {".dart", ".sql", ".ts", ".env", ".json", ".yaml", ".yml", ".py", ".sh"}

WHITELIST_PATHS = [
    "test/", "forensic_records/", "mock/", "mocks/",
    "pubspec.lock", ".env.example", "package-lock.json",
    "forensic_records/security/dirty_secrets_test/",  # test fixtures are exempt
]

# Audit log location (never committed)
AUDIT_LOG = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    ".veraprob", "security_audit.log"
)

# ── Level A: Precision Regex Patterns ─────────────────────────────────────────
REGEX_PATTERNS = [
    # Supabase service role / anon keys
    (r"sbp_[a-zA-Z0-9]{40}", "Supabase Secret Key (sbp_...)"),
    # JWT tokens (header present -> likely real token)
    (r"(eyJh|eyJi|eyJj)[a-zA-Z0-9_\-]{10,}\.[a-zA-Z0-9_\-]{10,}", "JWT Token"),
    # Generic API key patterns (key=, secret=, password=, token=, etc.)
    (
        r'(key|secret|password|passwd|pwd|token|auth|service_role|anon_key|api_key|access_key|private_key)'
        r'[\s]*[:=][\s]*["\'][a-zA-Z0-9_\-]{16,}["\']',
        "Generic API Key / Secret",
    ),
    # AWS keys
    (r"AKIA[0-9A-Z]{16}", "AWS Access Key ID"),
    # GitHub PATs (classic and fine-grained)
    (r"ghp_[a-zA-Z0-9]{36}", "GitHub Personal Access Token (ghp_)"),
    (r"github_pat_[a-zA-Z0-9_]{82}", "GitHub Fine-Grained PAT"),
    # Google API Keys
    (r"AIza[0-9A-Za-z_\-]{30,}", "Google API Key"),
]

COMPILED_PATTERNS = [(re.compile(p, re.IGNORECASE), desc) for p, desc in REGEX_PATTERNS]

# ── Level C: Magic Bytes / PEM Headers ────────────────────────────────────────
MAGIC_HEADERS = [
    "-----BEGIN RSA PRIVATE KEY-----",
    "-----BEGIN PRIVATE KEY-----",
    "-----BEGIN EC PRIVATE KEY-----",
    "-----BEGIN OPENSSH PRIVATE KEY-----",
    "-----BEGIN DSA PRIVATE KEY-----",
    "-----BEGIN PGP PRIVATE KEY BLOCK-----",
]

# ── Shannon Entropy ───────────────────────────────────────────────────────────
def shannon_entropy(data: str) -> float:
    """Calculate Shannon entropy of a string."""
    if not data:
        return 0.0
    freq = {}
    for ch in data:
        freq[ch] = freq.get(ch, 0) + 1
    length = len(data)
    return -sum((count / length) * math.log2(count / length) for count in freq.values())


def find_high_entropy_strings(line: str, threshold: float = 4.5, min_len: int = 20) -> list[str]:
    """
    Extract candidate strings (alphanumeric + common token chars) and
    return those exceeding the entropy threshold.
    """
    # Tokenise by common delimiters — grab chunks that look like keys
    candidates = re.findall(r"[a-zA-Z0-9+/=_\-]{20,}", line)
    return [c for c in candidates if len(c) >= min_len and shannon_entropy(c) >= threshold]


# ── Masking ───────────────────────────────────────────────────────────────────
def mask(value: str, keep: int = 4) -> str:
    """Return a masked version of a secret — never print real value."""
    if len(value) <= keep:
        return "*" * len(value)
    return value[:keep] + "*" * (len(value) - keep)


# ── Git Helpers ───────────────────────────────────────────────────────────────
def get_current_branch() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, check=True, encoding='utf-8'
        )
        return result.stdout.strip()
    except Exception:
        return "unknown"


def is_protected_context() -> bool:
    """Return True only on main branch or when a PR is open (upstream tracking)."""
    branch = get_current_branch()
    if branch == "main":
        return True
    # Heuristic: if branch tracks an upstream remote -> likely a PR branch
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            capture_output=True, text=True, encoding='utf-8'
        )
        return result.returncode == 0  # tracking remote -> PR candidate
    except Exception:
        return False


def get_staged_files() -> list[str]:
    """Return list of staged file paths."""
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            capture_output=True, text=True, check=True, encoding='utf-8'
        )
        return [f.strip() for f in result.stdout.splitlines() if f.strip()]
    except Exception:
        return []


def get_staged_content(filepath: str) -> list[str]:
    """Return staged content lines for a file."""
    try:
        result = subprocess.run(
            ["git", "show", f":{filepath}"],
            capture_output=True, text=True, check=True, encoding='utf-8'
        )
        return result.stdout.splitlines()
    except Exception:
        return []


# ── Whitelist Check ───────────────────────────────────────────────────────────
def is_whitelisted(filepath: str) -> bool:
    normalized = filepath.replace("\\", "/")
    return any(wl in normalized for wl in WHITELIST_PATHS)


# ── Audit Log ─────────────────────────────────────────────────────────────────
def write_audit_log(entries: list[str], bypass: bool = False, bypass_reason: str = "") -> None:
    os.makedirs(os.path.dirname(AUDIT_LOG), exist_ok=True)
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"
    with open(AUDIT_LOG, "a", encoding="utf-8") as f:
        f.write(f"\n{'='*70}\n")
        f.write(f"TIMESTAMP: {timestamp}\n")
        f.write(f"BRANCH: {get_current_branch()}\n")
        if bypass:
            f.write(f"ACTION: FORCE-BYPASS\n")
            f.write(f"REASON: {bypass_reason}\n")
        else:
            f.write(f"ACTION: BLOCKED\n")
        for entry in entries:
            f.write(f"  {entry}\n")


# ── Main Scanner ──────────────────────────────────────────────────────────────
def scan_file(filepath: str) -> list[dict]:
    """Scan a single file for secrets. Returns list of findings."""
    findings = []
    ext = os.path.splitext(filepath)[1].lower()

    if ext not in TARGET_EXTENSIONS:
        return findings

    lines = get_staged_content(filepath)

    for lineno, line in enumerate(lines, start=1):
        # ── Level C: Magic Bytes ─────────────────────────────────────────────
        for header in MAGIC_HEADERS:
            if header in line:
                findings.append({
                    "file": filepath,
                    "line": lineno,
                    "level": "C",
                    "type": "Private Key Header",
                    "masked": mask(header, 20),
                })

        # ── Level A: Regex Patterns ──────────────────────────────────────────
        for pattern, desc in COMPILED_PATTERNS:
            match = pattern.search(line)
            if match:
                findings.append({
                    "file": filepath,
                    "line": lineno,
                    "level": "A",
                    "type": desc,
                    "masked": mask(match.group(0)),
                })

        # ── Level B: Shannon Entropy ─────────────────────────────────────────
        high_entropy = find_high_entropy_strings(line)
        for candidate in high_entropy:
            findings.append({
                "file": filepath,
                "line": lineno,
                "level": "B",
                "type": f"High-Entropy String (H={shannon_entropy(candidate):.2f})",
                "masked": mask(candidate),
            })

    return findings


# ── Entry Point ───────────────────────────────────────────────────────────────
def main() -> int:
    parser = argparse.ArgumentParser(description="VeraProb Forensic Secrets Scanner")
    parser.add_argument(
        "--force-bypass",
        metavar="REASON",
        help="Bypass the scanner with an audited justification (INV-28 override)"
    )
    args = parser.parse_args()

    print(f"\n{BOLD}{'='*62}{NC}")
    print(f"{BOLD}  VeraProb — Forensic Secrets Scanner (INV-28){NC}")
    print(f"{BOLD}{'='*62}{NC}")

    # ── Gate: only run on protected context ──────────────────────────────────
    if not is_protected_context():
        branch = get_current_branch()
        print(f"\n{GREEN}  [OK] Branch '{branch}' is not protected — scanner skipped.{NC}")
        print(f"  (Scanner runs only on 'main' or PR-tracked branches)\n")
        return 0

    staged = get_staged_files()
    if not staged:
        print(f"\n{GREEN}  [OK] No staged files — nothing to scan.{NC}\n")
        return 0

    print(f"\n  Branch: {BOLD}{get_current_branch()}{NC} (protected context)")
    print(f"  Scanning {len(staged)} staged file(s)...\n")

    all_findings: list[dict] = []
    scanned = 0

    for filepath in staged:
        if is_whitelisted(filepath):
            print(f"  {YELLOW}[SKIP]{NC}  {filepath} (whitelisted)")
            continue
        findings = scan_file(filepath)
        all_findings.extend(findings)
        scanned += 1

    # ── Report ────────────────────────────────────────────────────────────────
    if all_findings:
        print(f"\n{RED}{BOLD}  [X] SECRETS DETECTED — Commit Blocked{NC}")
        print(f"{'─'*62}")
        log_entries = []
        for f in all_findings:
            entry = f"[LEVEL-{f['level']}] {f['file']}:{f['line']} — {f['type']} -> {f['masked']}"
            print(f"  {RED}{entry}{NC}")
            log_entries.append(entry)

        print(f"\n{BOLD}  How to fix:{NC}")
        print(f"  1. Replace hardcoded secret with an environment variable.")
        print(f"  2. Use Supabase Vault for sensitive credentials.")
        print(f"  3. Add secret to .env (never commit .env).")
        print(f"  4. If false-positive, use: python scripts/scan_secrets.py --force-bypass \"reason\"\n")

        if args.force_bypass:
            write_audit_log(log_entries, bypass=True, bypass_reason=args.force_bypass)
            print(f"{YELLOW}  ⚠  FORCE-BYPASS activated. Reason: '{args.force_bypass}'{NC}")
            print(f"  Audit logged to: {AUDIT_LOG}\n")
            return 0

        write_audit_log(log_entries)
        print(f"  Audit logged to: {AUDIT_LOG}\n")
        return 1

    print(f"\n{GREEN}  [OK] No secrets detected in {scanned} file(s). Clean commit.{NC}")
    print(f"{'='*62}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
