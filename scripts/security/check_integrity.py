#!/usr/bin/env python3
import os
import sys

# ── Configuration ─────────────────────────────────────────────────────────────
TARGET_EXTENSIONS = {".dart", ".py", ".sh", ".sql", ".yaml", ".yml", ".json", ".md", ".env"}
IGNORE_DIRS = {
    ".git", ".dart_tool", "build", ".veraprob", "ios", "android", 
    "linux", "windows", "macos", ".docker-mcp", "node_modules", 
    "vendor", ".idea", ".vscode", ".venv", "venv"
}

# ── Colors ───────────────────────────────────────────────────────────────────
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BOLD = '\033[1m'
NC = '\033[0m'

def check_file(filepath):
    """Checks a file for CRLF and encoding integrity."""
    issues = []
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
            
            # 1. Check for CRLF (\r\n)
            if b'\r\n' in content:
                issues.append("CRLF line endings detected (Standard is LF)")
            
            # 2. Check for UTF-8 validity
            try:
                content.decode('utf-8')
            except UnicodeDecodeError:
                issues.append("Invalid UTF-8 encoding (Possible legacy Windows-1252/Latin-1)")
                
    except Exception as e:
        issues.append(f"Could not read file: {e}")
        
    return issues

def main():
    if sys.platform == "win32":
        import io
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    print(f"\n{BOLD}🛡️  VeraProb Integrity Guard (Tier 1 Enforcement){NC}")
    print(f"{'─' * 55}")
    
    root_dir = "."
    violations = 0
    scanned = 0
    
    try:
        import subprocess
        # Tracked files and untracked (but not ignored) files
        tracked = subprocess.check_output(['git', 'ls-files']).decode('utf-8').splitlines()
        untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard']).decode('utf-8').splitlines()
        all_files = tracked + untracked
        
        files_to_check = [f for f in all_files if os.path.isfile(f) and not any(part in IGNORE_DIRS for part in f.replace('\\', '/').split('/'))]
    except Exception:
        # Fallback if git is not available
        files_to_check = []
        for root, dirs, files in os.walk(root_dir):
            dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
            for file in files:
                files_to_check.append(os.path.join(root, file))

    for filepath in files_to_check:
        ext = os.path.splitext(filepath)[1].lower()
        if ext in TARGET_EXTENSIONS:
            scanned += 1
            issues = check_file(filepath)
            
            if issues:
                violations += 1
                print(f"  {RED}❌ {filepath}{NC}")
                for issue in issues:
                    print(f"     └─ {issue}")

    print(f"{'─' * 55}")
    if violations == 0:
        print(f"  {GREEN}✓ {scanned} files checked. Integrity is 100%.{NC}\n")
        sys.exit(0)
    else:
        print(f"  {RED}{BOLD}VETO:{NC} {violations} files failed integrity checks.")
        print(f"  {YELLOW}Action:{NC} Use 'git add --renormalize .' or your IDE to fix encoding/LF.\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
