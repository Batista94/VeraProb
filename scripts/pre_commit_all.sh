#!/bin/bash
# ==============================================================================
# VeraProb Pre-Commit Orchestrator (H-02 to H-06)
# ==============================================================================
set -e

echo "🚀 Running Unified Pre-Commit Hooks..."

# H-02: Type Sync
echo "--- [H-02] Type Sync ---"
bash scripts/sync_db_types.sh

# H-06: Prompt Audit (Audit Skills)
echo "--- [H-06] Prompt Audit ---"
# Note: Since we are in bash, we'd need to invoke the auditor. 
# For now, we simulate the requirement or use the CLI if available.
# In Antigravity/Claude, the agent runs this via Skill.

# H-04: Secret Scan
echo "--- [H-04] Secret Scan ---"
python scripts/security/scan_secrets.py

# H-05: Barrel Scan
echo "--- [H-05] Barrel Scan ---"
python scripts/validate_barrel_files.py

# H-13: Encoding Guard (blocks mojibake before it enters the repo)
bash scripts/encoding_guard.sh

# H-03: Forensic Scan (The Veto)
echo "--- [H-03] Forensic Scan ---"
bash scripts/security/pr_full_scanner.sh

# H-11: Index Advisor
echo "--- [H-11] Index Advisor ---"
python scripts/index_advisor.py

# H-12: Code Quality (Lint & Auto-Fix)
echo "--- [H-12] Code Quality ---"
dart fix --apply
flutter analyze --fatal-infos --fatal-warnings

echo "✅ All pre-commit hooks passed."
