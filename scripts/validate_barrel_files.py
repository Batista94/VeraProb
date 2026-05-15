#!/usr/bin/env python3
import os
import re
import sys
import subprocess
import argparse

# ── Configuration ────────────────────────────────────────────────────────────
LIB_DIR = "lib"
DOMAIN_DIR = "lib/domain"
IGNORE_PATTERNS = [".g.dart", ".freezed.dart"]
EXPORT_PATTERN = re.compile(r"export\s+['\"](.+?)['\"];")
IMPORT_PATTERN = re.compile(r"import\s+['\"](.+?)['\"];")
PROVIDER_PATTERN = re.compile(r"@riverpod|Provider|NotifierProvider|StateNotifierProvider")

# LEI DO ENCAPSULAMENTO (Anti-Leak)
ENCAPSULATION_PATTERN = re.compile(r"_internal\.dart|/private/|/src/")

# ── Color codes ──────────────────────────────────────────────────────────────
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
GREEN = '\033[0;32m'
BLUE = '\033[0;34m'
BOLD = '\033[1m'
NC = '\033[0m'

def get_changed_files(branch="main"):
    # Priority: Stdin (passed from bash wrapper)
    if not sys.stdin.isatty():
        try:
            stdin_data = sys.stdin.read().strip()
            if stdin_data:
                files = [f.replace("\\", "/").strip() for f in stdin_data.splitlines() if f.strip()]
                files = [f for f in files if f.startswith(LIB_DIR) and f.endswith(".dart")]
                return list(set([f for f in files if not any(p in f for p in IGNORE_PATTERNS)]))
        except Exception:
            pass

    try:
        # Fallback to manual git check if not piped
        output = subprocess.check_output(["git", "diff", "--name-only", branch], text=True, encoding='utf-8')
        files = [f.replace("\\", "/").strip() for f in output.splitlines()]
        
        untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"], text=True, encoding='utf-8')
        files.extend([f.replace("\\", "/").strip() for f in untracked.splitlines()])
        
        files = [f for f in files if f.startswith(LIB_DIR) and f.endswith(".dart")]
        return list(set([f for f in files if not any(p in f for p in IGNORE_PATTERNS)]))
    except Exception as e:
        print(f"{YELLOW}Warning: Failed to get changed files via git: {e}{NC}")
        return []

def resolve_path(current_file, target_path):
    current_file = current_file.replace("\\", "/")
    if target_path.startswith("package:veraprob/"):
        path = os.path.join(LIB_DIR, target_path.replace("package:veraprob/", ""))
        return path.replace("\\", "/")
    if target_path.startswith("dart:"):
        return None
    if target_path.startswith("package:"):
        return None
    
    # Relative path
    dirname = os.path.dirname(current_file)
    resolved = os.path.normpath(os.path.join(dirname, target_path))
    return resolved.replace("\\", "/")

def build_graph(files_to_scan):
    export_graph = {}
    import_map = {}
    provider_map = {}
    raw_exports = {}

    for file_path in files_to_scan:
        file_path = file_path.replace("\\", "/")
        if not os.path.exists(file_path):
            continue
            
        try:
            with open(file_path, "rb") as f:
                raw_content = f.read()
                # Robust decoding sequence
                for encoding in ["utf-8-sig", "utf-8", "latin-1"]:
                    try:
                        content = raw_content.decode(encoding)
                        break
                    except UnicodeDecodeError:
                        continue
                else:
                    content = raw_content.decode("utf-8", errors="ignore")
        except Exception:
            continue
            
        # Exports
        exports = EXPORT_PATTERN.findall(content)
        export_graph[file_path] = []
        raw_exports[file_path] = exports
        for exp in exports:
            resolved = resolve_path(file_path, exp)
            if resolved:
                export_graph[file_path].append(resolved)
        
        # Imports
        imports = IMPORT_PATTERN.findall(content)
        import_map[file_path] = []
        for imp in imports:
            resolved = resolve_path(file_path, imp)
            if resolved:
                import_map[file_path].append(resolved)
        
        # Providers
        if PROVIDER_PATTERN.search(content):
            provider_map[file_path] = True
                
    return export_graph, import_map, provider_map, raw_exports

def find_cycle(graph):
    visited = set()
    recursion_stack = []
    
    def visit(node):
        if node in recursion_stack:
            idx = recursion_stack.index(node)
            return recursion_stack[idx:] + [node]
        if node in visited:
            return None
            
        visited.add(node)
        recursion_stack.append(node)
        
        for neighbor in graph.get(node, []):
            res = visit(neighbor)
            if res: return res
            
        recursion_stack.pop()
        return None

    # Sort nodes to ensure deterministic behavior
    for node in sorted(graph.keys()):
        cycle = visit(node)
        if cycle: return cycle
    return None

def check_internal_barrel_import(file_path, imports):
    # Rule: features/auth/domain/x.dart cannot import features/auth/auth.dart
    parts = file_path.replace("\\", "/").split("/")
    if len(parts) > 3 and parts[0] == "lib" and parts[1] == "features":
        feature_name = parts[2]
        barrel_file = f"lib/features/{feature_name}/{feature_name}.dart"
        
        # Don't check the barrel file itself
        if file_path == barrel_file:
            return None
            
        for imp in imports:
            if imp == barrel_file:
                return barrel_file
    return None

def check_encapsulation(export_path):
    """Verifica se a exportação viola detalhes internos (INV-13)."""
    return ENCAPSULATION_PATTERN.search(export_path) is not None

def main():
    # Fix for Windows console encoding
    try:
        if sys.stdout.encoding != 'utf-8':
            import io
            sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    except Exception:
        pass

    parser = argparse.ArgumentParser()
    parser.add_argument("--branch", default="dev")
    args = parser.parse_args()
    
    # is_strict is true only on main/CI
    is_strict = args.branch == "main" or os.getenv("GITHUB_ACTIONS") == "true"
    
    try:
        changed_files = get_changed_files(args.branch)
        if not changed_files:
            # Silent success if no files to check
            sys.exit(0)
            
        print(f"  Scanning {len(changed_files)} files for barrel violations...")
        export_graph, import_map, provider_map, raw_exports = build_graph(changed_files)
        
        violations = []
        warnings = []
        
        # ── 1. LEI DO DOMÍNIO EXPLÍCITO (No-Barrel-in-Domain) ───────────────
        for file_path in changed_files:
            if file_path.startswith(DOMAIN_DIR):
                is_barrel = (
                    file_path.endswith("index.dart") or 
                    file_path.endswith(f"{os.path.basename(os.path.dirname(file_path))}.dart")
                )
                if is_barrel and export_graph.get(file_path):
                    violations.append(
                        f"[VETO ARQUITETURAL - INV-13]: Barrel file PROIBIDO no Domínio.\n"
                        f"   Arquivo: {file_path}\n"
                        f"   Justificativa: Dependências de domínio devem ser explícitas para evitar acoplamento invisível."
                    )

        # ── 2. LEI DO ENCAPSULAMENTO (Anti-Leak) ──────────────────────────────
        for file_path, exports in raw_exports.items():
            for exp in exports:
                if check_encapsulation(exp):
                    violations.append(
                        f"[VETO ARQUITETURAL - INV-13]: Vazamento de escopo detectado (Anti-Leak).\n"
                        f"   Arquivo: {file_path} exporta {exp}\n"
                        f"   Justificativa: Proibido exportar detalhes internos (_internal, private, src)."
                    )

        # ── 3. LEI DA ACICLICIDADE (Cycles) ──────────────────────────────────
        cycle = find_cycle(export_graph)
        if cycle:
            graph_str = " -> ".join(cycle)
            violations.append(f"[VETO ARQUITETURAL - INV-13]: Dependência circular detectada em arquivos barrel.\n   Grafo: {graph_str}")

        # 4. Veto Internal Barrel Import
        for file_path, imports in import_map.items():
            bad_barrel = check_internal_barrel_import(file_path, imports)
            if bad_barrel:
                violations.append(f"[VETO ARQUITETURAL - INV-13]: Importação circular de barrel interno.\n   Arquivo: {file_path} importa seu próprio barrel {bad_barrel}")

        # 5. Riverpod Provider Isolation (INV-11)
        for barrel, exports in export_graph.items():
            providers_exported = [e for e in exports if provider_map.get(e)]
            if len(providers_exported) > 1:
                for p1 in providers_exported:
                    for p2 in providers_exported:
                        if p1 == p2: continue
                        if p2 in import_map.get(p1, []):
                            warnings.append(f"[INV-11]: Possível circularidade de Providers no barrel {barrel}.\n   {p1} importa {p2}, ambos exportados pelo mesmo barrel.")

        # Output Results
        if violations:
            for v in violations:
                print(f"{RED}{BOLD}❌ {v}{NC}")
            if is_strict:
                sys.exit(1) # Hard failure in strict mode
            else:
                print(f"{YELLOW}Aviso: Bloqueio ignorado em branch de desenvolvimento.{NC}")
                
        if warnings:
            for w in warnings:
                print(f"{YELLOW}{BOLD}⚠️ {w}{NC}")
                
        if not violations and not warnings:
            print(f"{GREEN}✔ Estrutura de exportação limpa e em conformidade com INV-13.{NC}")
            
        sys.exit(0)
    except Exception as e:
        # Internal script error should NOT cause a Veto by default, but should be visible
        print(f"{RED}{BOLD}[INTERNAL ERROR] Barrel Validator failed: {e}{NC}")
        # Return 2 to distinguish from "Violations Found (1)"
        sys.exit(2)

if __name__ == "__main__":
    main()
