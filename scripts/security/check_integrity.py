#!/usr/bin/env python3
import os
import sys

# ── Configuration ─────────────────────────────────────────────────────────────
TARGET_EXTENSIONS = {".dart", ".py", ".sh", ".sql", ".yaml", ".yml", ".json", ".md", ".env"}
IGNORE_DIRS = {".git", ".dart_tool", "build", ".veraprob", "ios", "android"}

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
    print(f"\n{BOLD}🛡️  VeraProb Integrity Guard (Tier 1 Enforcement){NC}")
    print(f"{'─' * 55}")
    
    root_dir = "."
    violations = 0
    scanned = 0
    
    for root, dirs, files in os.walk(root_dir):
        # Skip ignored directories
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
        
        for file in files:
            ext = os.path.splitext(file)[1].lower()
            if ext in TARGET_EXTENSIONS:
                filepath = os.path.join(root, file)
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
