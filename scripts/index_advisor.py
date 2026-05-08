#!/usr/bin/env python3
"""
VeraProb — Index Advisor (Performance Guardian)
INV-12: Performance as a Physical Engineering Metric.

Scans staged .sql and .dart files for queries on critical high-volume tables,
runs EXPLAIN (FORMAT JSON) against local Supabase Postgres, and vetoes
Sequential Scans or missing organization_id filters (INV-2).

Branch behavior:
  - Feature branches: WARNING only (exit 0)
  - main/develop/PR:  VETO (exit 1)
"""
import hashlib
import json
import os
import re
import subprocess
import sys

if sys.stdout.encoding != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

# ── Configuration ────────────────────────────────────────────────────────────
DB_HOST = os.environ.get("PGHOST", "127.0.0.1")
DB_PORT = os.environ.get("PGPORT", "54322")
DB_NAME = os.environ.get("PGDATABASE", "postgres")
DB_USER = os.environ.get("PGUSER", "postgres")
DB_PASS = os.environ.get("PGPASSWORD", "postgres")

CRITICAL_TABLES = [
    "evidences", "telemetry", "ledger", "shadow_executions",
    "sla_audit_ledger", "sla_audit_ledger_v2",
    "raw_telemetry_payloads", "shadow_verdicts",
    "telegram_evidence_uploads", "telegram_evidence_links",
    "telegram_evidence_metadata", "shadow_mode_simulations",
]

CACHE_FILE = ".index_advisor_cache.json"

# ── Colors ───────────────────────────────────────────────────────────────────
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
GREEN = '\033[0;32m'
CYAN = '\033[0;36m'
BOLD = '\033[1m'
NC = '\033[0m'

# ── Regex patterns ───────────────────────────────────────────────────────────
SQL_QUERY_RE = re.compile(
    r"""(SELECT\b[^;]{10,};?)""",
    re.IGNORECASE | re.DOTALL,
)
# Dart Supabase calls: .from('table').select(...).eq(...) chains
DART_SUPABASE_RE = re.compile(
    r"""\.from\(\s*['"](\w+)['"]\s*\)([^;]{5,}?;)""",
    re.DOTALL,
)
# Table references in SQL
TABLE_REF_RE = re.compile(
    r"""\b(?:FROM|JOIN)\s+(?:public\.)?(\w+)""",
    re.IGNORECASE,
)


def get_branch():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
        ).strip()
    except Exception:
        return "unknown"


def is_strict_mode():
    branch = get_branch()
    return branch in ("main", "develop") or os.environ.get("CI") == "true"


def get_staged_files():
    try:
        out = subprocess.check_output(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"], text=True
        )
        return [f.strip() for f in out.splitlines() if f.strip()]
    except Exception:
        return []


def load_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_cache(cache):
    try:
        with open(CACHE_FILE, "w") as f:
            json.dump(cache, f, indent=2)
    except Exception:
        pass


def query_hash(sql):
    return hashlib.sha256(sql.encode()).hexdigest()[:16]


def extract_queries_from_sql(content):
    """Extract SELECT queries from .sql migration files."""
    queries = []
    for m in SQL_QUERY_RE.finditer(content):
        q = m.group(1).strip()
        tables = TABLE_REF_RE.findall(q)
        critical = [t for t in tables if t.lower() in CRITICAL_TABLES]
        if critical:
            queries.append((q, critical))
    return queries


def dart_chain_to_pseudo_sql(table, chain):
    """Convert Dart Supabase method chain to pseudo-SQL for EXPLAIN."""
    cols = "*"
    select_m = re.search(r"\.select\(\s*['\"](.+?)['\"]", chain)
    if select_m:
        cols = select_m.group(1)

    wheres = []
    for eq_m in re.finditer(r"\.eq\(\s*['\"](\w+)['\"]", chain):
        wheres.append(f"{eq_m.group(1)} = 'placeholder'")
    for gt_m in re.finditer(r"\.gt[e]?\(\s*['\"](\w+)['\"]", chain):
        wheres.append(f"{gt_m.group(1)} > 'placeholder'")
    for lt_m in re.finditer(r"\.lt[e]?\(\s*['\"](\w+)['\"]", chain):
        wheres.append(f"{lt_m.group(1)} < 'placeholder'")
    for in_m in re.finditer(r"\.(?:in_|inFilter)\(\s*['\"](\w+)['\"]", chain):
        wheres.append(f"{in_m.group(1)} IN ('placeholder')")

    order = ""
    order_m = re.search(r"\.order\(\s*['\"](\w+)['\"]", chain)
    if order_m:
        order = f" ORDER BY {order_m.group(1)}"

    limit = ""
    limit_m = re.search(r"\.limit\(\s*(\d+)", chain)
    if limit_m:
        limit = f" LIMIT {limit_m.group(1)}"

    where_clause = (" WHERE " + " AND ".join(wheres)) if wheres else ""
    return f"SELECT {cols} FROM {table}{where_clause}{order}{limit}"


def extract_queries_from_dart(content):
    """Extract pseudo-SQL from Dart Supabase calls."""
    queries = []
    for m in DART_SUPABASE_RE.finditer(content):
        table = m.group(1)
        if table.lower() in CRITICAL_TABLES:
            chain = m.group(2)
            pseudo = dart_chain_to_pseudo_sql(table, chain)
            queries.append((pseudo, [table]))
    return queries


def run_explain(sql):
    """Run EXPLAIN (FORMAT JSON) via psql and return the plan."""
    explain_sql = f"EXPLAIN (FORMAT JSON) {sql}"
    env = os.environ.copy()
    env["PGPASSWORD"] = DB_PASS
    try:
        result = subprocess.run(
            ["psql", "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER,
             "-d", DB_NAME, "-t", "-A", "-c", explain_sql],
            capture_output=True, text=True, timeout=10, env=env,
        )
        if result.returncode != 0:
            return None, result.stderr.strip()
        return json.loads(result.stdout.strip()), None
    except FileNotFoundError:
        return None, "psql not found — is Supabase CLI / PostgreSQL client installed?"
    except json.JSONDecodeError:
        return None, "Failed to parse EXPLAIN output"
    except subprocess.TimeoutExpired:
        return None, "EXPLAIN timed out (>10s)"
    except Exception as e:
        return None, str(e)


def run_analyze():
    """Run ANALYZE on critical tables so EXPLAIN stats are fresh."""
    env = os.environ.copy()
    env["PGPASSWORD"] = DB_PASS
    tables = ", ".join(CRITICAL_TABLES[:6])  # top tables only
    try:
        subprocess.run(
            ["psql", "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER,
             "-d", DB_NAME, "-c", f"ANALYZE {tables};"],
            capture_output=True, text=True, timeout=15, env=env,
        )
    except Exception:
        pass  # best-effort


def find_seq_scans(plan_node, results=None):
    """Recursively find Seq Scan nodes on critical tables."""
    if results is None:
        results = []
    node_type = plan_node.get("Node Type", "")
    relation = plan_node.get("Relation Name", "").lower()
    alias = plan_node.get("Alias", "").lower()
    if node_type == "Seq Scan" and (relation in CRITICAL_TABLES or alias in CRITICAL_TABLES):
        results.append({
            "table": relation or alias,
            "cost": plan_node.get("Total Cost", 0),
            "rows": plan_node.get("Plan Rows", 0),
            "filter": plan_node.get("Filter", ""),
        })
    for child in plan_node.get("Plans", []):
        find_seq_scans(child, results)
    return results


def check_org_id_filter(sql):
    """INV-2: Verify organization_id is present in the query."""
    return bool(re.search(r"organization_id", sql, re.IGNORECASE))


def suggest_index(table, plan_node):
    """Suggest a CREATE INDEX based on the filter condition."""
    filt = plan_node.get("Filter", "")
    cols = re.findall(r"\((\w+)\)", filt) or re.findall(r"(\w+)\s*=", filt)
    if not cols:
        cols = ["organization_id"]
    col_list = ", ".join(dict.fromkeys(cols))  # dedupe, preserve order
    idx_name = f"idx_{table}_{'_'.join(dict.fromkeys(cols))}"
    return f"CREATE INDEX CONCURRENTLY {idx_name} ON public.{table} ({col_list});"


def analyze_query(sql, tables, cache, strict):
    """Analyze a single query. Returns list of issues."""
    h = query_hash(sql)
    if h in cache:
        return cache[h]

    issues = []

    # INV-2: org_id check
    if not check_org_id_filter(sql):
        issues.append({
            "type": "INV-2_MISSING_ORG_ID",
            "severity": "VETO" if strict else "WARNING",
            "message": f"Query on {tables} lacks organization_id filter (INV-2 violation).",
            "sql": sql,
        })

    # EXPLAIN analysis
    plan, err = run_explain(sql)
    if err:
        issues.append({
            "type": "EXPLAIN_ERROR",
            "severity": "WARNING",
            "message": f"Could not EXPLAIN: {err}",
            "sql": sql,
        })
        cache[h] = issues
        return issues

    top_plan = plan[0]["Plan"] if plan else {}
    seq_scans = find_seq_scans(top_plan)

    for scan in seq_scans:
        suggestion = suggest_index(scan["table"], scan)
        issues.append({
            "type": "SEQ_SCAN",
            "severity": "VETO" if strict else "WARNING",
            "message": (
                f"Seq Scan on '{scan['table']}' — "
                f"cost={scan['cost']:.0f}, rows≈{scan['rows']}"
            ),
            "suggestion": suggestion,
            "sql": sql,
        })

    cache[h] = issues
    return issues


def print_issue(issue):
    sev = issue["severity"]
    color = RED if sev == "VETO" else YELLOW
    icon = "🚫" if sev == "VETO" else "⚠️"
    print(f"\n  {icon} {color}[{sev}]{NC} {BOLD}{issue['type']}{NC}")
    print(f"     {issue['message']}")
    if "suggestion" in issue:
        print(f"     {CYAN}💡 Fix: {issue['suggestion']}{NC}")
    # Truncated SQL preview
    sql_preview = issue.get("sql", "")[:120].replace("\n", " ")
    print(f"     {BOLD}Query:{NC} {sql_preview}...")


def main():
    print(f"\n{BOLD}🔍 VeraProb Index Advisor (INV-12 Performance Guardian){NC}")
    print(f"{'─' * 60}")

    staged = get_staged_files()
    targets = [f for f in staged if f.endswith(".sql") or f.endswith(".dart")]

    if not targets:
        print(f"  {GREEN}✓ No staged .sql/.dart files — nothing to scan.{NC}\n")
        sys.exit(0)

    strict = is_strict_mode()
    mode_label = f"{RED}STRICT (main/CI){NC}" if strict else f"{YELLOW}ADVISORY (feature){NC}"
    print(f"  Mode: {mode_label}")
    print(f"  Files: {len(targets)} staged")

    # Ensure fresh stats
    run_analyze()

    cache = load_cache()
    all_issues = []

    for filepath in targets:
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
        except Exception:
            continue

        queries = []
        if filepath.endswith(".sql"):
            queries = extract_queries_from_sql(content)
        elif filepath.endswith(".dart"):
            queries = extract_queries_from_dart(content)

        for sql, tables in queries:
            issues = analyze_query(sql, tables, cache, strict)
            for issue in issues:
                issue["file"] = filepath
            all_issues.extend(issues)

    save_cache(cache)

    vetoes = [i for i in all_issues if i["severity"] == "VETO"]
    warnings = [i for i in all_issues if i["severity"] == "WARNING"]

    if not all_issues:
        print(f"\n  {GREEN}✓ All queries use proper indexes. Performance OK.{NC}\n")
        sys.exit(0)

    for issue in all_issues:
        print_issue(issue)

    print(f"\n{'─' * 60}")
    print(f"  Summary: {RED}{len(vetoes)} veto(s){NC}, {YELLOW}{len(warnings)} warning(s){NC}")

    if vetoes:
        print(f"\n  {RED}{BOLD}❌ COMMIT BLOCKED — fix performance issues above.{NC}\n")
        sys.exit(1)

    print(f"\n  {YELLOW}⚠️  Warnings only — commit allowed on feature branch.{NC}\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
