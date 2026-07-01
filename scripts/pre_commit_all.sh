#!/bin/bash
# ==============================================================================
# VeraProb Pre-Commit Orchestrator (H-02 to H-06)
# ==============================================================================
set -e

find_real_python() {
  for cmd in python3 py.exe python; do
    if command -v "$cmd" >/dev/null 2>&1; then
      if "$cmd" --version 2>&1 | grep -q "Python 3"; then
        echo "$cmd"
        return 0
      fi
    fi
  done
  
  local common_paths=(
    "$LOCALAPPDATA/Programs/Python"/Python*/python.exe
    "$LOCALAPPDATA/Python"/pythoncore-*/python.exe
    "$HOME/AppData/Local/Programs/Python"/Python*/python.exe
    "$HOME/AppData/Local/Python"/pythoncore-*/python.exe
    "$HOME/anaconda3/python.exe"
    "/c/Python"/Python*/python.exe
  )
  for p in "${common_paths[@]}"; do
    if [ -f "$p" ]; then
      if "$p" --version 2>&1 | grep -q "Python 3"; then
        echo "$p"
        return 0
      fi
    fi
  done
  
  echo "python"
}

PYTHON_CMD=$(find_real_python)

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
$PYTHON_CMD scripts/security/scan_secrets.py

# H-05: Barrel Scan
echo "--- [H-05] Barrel Scan ---"
$PYTHON_CMD scripts/validate_barrel_files.py

# H-13: Integrity Guard (encoding & line endings)
echo "--- [H-13] Integrity Guard ---"
$PYTHON_CMD scripts/security/check_integrity.py

# H-03: Forensic Scan (The Veto)
echo "--- [H-03] Forensic Scan ---"
bash scripts/security/pr_full_scanner.sh

# H-11: Index Advisor
echo "--- [H-11] Index Advisor ---"
$PYTHON_CMD scripts/index_advisor.py

# H-12: Code Quality (Lint & Auto-Fix)
echo "--- [H-12] Code Quality ---"
FLUTTER_CMD="flutter"
DART_CMD="dart"
if command -v cmd.exe >/dev/null 2>&1; then
  FLUTTER_CMD="cmd.exe /c flutter.bat"
  DART_CMD="cmd.exe /c dart.bat"
fi
$DART_CMD fix --apply
$FLUTTER_CMD analyze --fatal-infos --fatal-warnings

echo "✅ All pre-commit hooks passed."
