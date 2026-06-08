/**
 * scanner_engine.js — Single-pass deterministic PR scanner.
 *
 * MISSION: Scan all changed files against pr_patterns.json rules and return
 * a structured JSON result. The bash wrapper (pr_full_scanner.sh) consumes
 * this JSON and handles color output + verdict.
 *
 * Usage:
 *   echo "file1.dart\nfile2.dart" | node scanner_engine.js --base-branch=main
 *
 * Output (stdout, JSON only):
 *   {"blocks":2,"warns":0,"has_regression":true,"violations":[...],"regression_files":[...]}
 */

const fs = require("fs");
const path = require("path");

// ── Argument Parsing ─────────────────────────────────────────────────────────

const args = process.argv.slice(2);
let baseBranch = "main";
for (const arg of args) {
  if (arg.startsWith("--base-branch=")) {
    baseBranch = arg.split("=")[1];
  }
}

// ── Load Patterns ────────────────────────────────────────────────────────────

const patternsPath = path.join(__dirname, "pr_patterns.json");
if (!fs.existsSync(patternsPath)) {
  console.error("Error: scripts/pr_patterns.json not found.");
  process.exit(1);
}
const patterns = JSON.parse(fs.readFileSync(patternsPath, "utf8"));

Object.entries(patterns).forEach(([name, config]) => {
  if (config.pattern && (config.pattern.includes("\n") || config.pattern.includes("\r"))) {
    console.error(`[ERROR] Pattern '${name}' contains illegal JSON escapes. Fix pr_patterns.json.`);
    process.exit(1);
  }
});

// ── Read Changed Files from stdin ────────────────────────────────────────────

const changedFiles = fs
  .readFileSync(0, "utf8")
  .split("\n")
  .map((f) => f.trim())
  .filter((f) => f.length > 0);

if (changedFiles.length === 0) {
  // No changes — return empty result
  console.log(
    JSON.stringify({
      blocks: 0,
      warns: 0,
      has_regression: false,
      violations: [],
      regression_files: [],
    }),
  );
  process.exit(0);
}

// ── Global deny-all table set (loaded from all migration COMMENT ON TABLE) ──
let _denyAllTables = null;
function getDenyAllTables() {
  if (_denyAllTables) return _denyAllTables;
  _denyAllTables = new Set();
  const migDir = path.join(path.dirname(path.dirname(__dirname)), "supabase", "migrations");
  if (fs.existsSync(migDir)) {
    for (const f of fs.readdirSync(migDir).filter(f => f.endsWith('.sql'))) {
      const txt = fs.readFileSync(path.join(migDir, f), 'utf8');
      const re = /COMMENT\s+ON\s+TABLE\s+(?:public\.)?([\w]+)\s+IS\s+'[^']*(?:deny-all|service\.role only|no authenticated access)[^']*'/gi;
      let m;
      while ((m = re.exec(txt)) !== null) _denyAllTables.add(m[1].toLowerCase());
    }
  }
  return _denyAllTables;
}

// ── Global set of tables with policies in any migration ──
let _tablesWithPolicies = null;
function getTablesWithPolicies() {
  if (_tablesWithPolicies) return _tablesWithPolicies;
  _tablesWithPolicies = new Set();
  const migDir = path.join(path.dirname(path.dirname(__dirname)), "supabase", "migrations");
  if (fs.existsSync(migDir)) {
    for (const f of fs.readdirSync(migDir).filter(f => f.endsWith('.sql'))) {
      const txt = fs.readFileSync(path.join(migDir, f), 'utf8');
      const re = /CREATE\s+POLICY[^;]+ON\s+(?:public\.)?([\w]+)/gi;
      let m;
      while ((m = re.exec(txt)) !== null) _tablesWithPolicies.add(m[1].toLowerCase());
    }
  }
  return _tablesWithPolicies;
}

// ── Pre-compile Patterns ─────────────────────────────────────────────────────

function safeRegExp(p) {
  if (!p) return { test: () => true };
  try {
    const sanitized = String(p).replace(/\x08/g, "\\b");
    return new RegExp(sanitized);
  } catch (e) {
    console.error(`[ERROR] Invalid regex pattern: ${p}`);
    return { test: () => false };
  }
}

const compiledPatterns = Object.entries(patterns).map(([name, config]) => ({
  name,
  config,
  regex: safeRegExp(config.pattern),
  mustAlsoContain: config.type === "absence_check" ? safeRegExp(config.must_also_contain) : null,
  requiresSupabaseContent: config.requires_supabase_content ? config.requires_supabase_content.map(safeRegExp) : null,
  pathFilter: config.path_filter ? new RegExp(config.path_filter) : null,
  excludePathPattern: config.exclude_path_pattern ? new RegExp(config.exclude_path_pattern, "i") : null
}));

// ── Scan ─────────────────────────────────────────────────────────────────────

const violations = [];
const bypassKeywords = [
  "// Physical Metric",
  "- Double Required",
  "Bridge Conversion",
  "Probability Score",
  "INV-DB: zero-downtime-verified",
];

changedFiles.forEach((file) => {
  // Skip generated files
  if (file.endsWith(".g.dart") || file.endsWith(".freezed.dart")) return;
  if (!fs.existsSync(file)) return;
  if (!fs.statSync(file).isFile()) return;

  const content = fs.readFileSync(file, "utf8");
  const lines = content.split(/\r?\n/);

  compiledPatterns.forEach(({name, config, regex, mustAlsoContain, requiresSupabaseContent, pathFilter, excludePathPattern}) => {
    // Path filtering
    if (pathFilter && !pathFilter.test(file))
      return;
    if (excludePathPattern && excludePathPattern.test(file))
      return;
    if (config.exclude_files && config.exclude_files.some((exclude) => file.includes(exclude)))
      return;
    if (config.files_containing && !config.files_containing.some((term) => file.includes(term)))
      return;

    // ── Absence Check (INV-1 / INV-26-REPO / INV-30) ──
    if (config.type === "absence_check") {
      const strippedContent = content
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/\/\/\/.*$/gm, "")
        .replace(/\/\/.*$/gm, "");

      if (!regex.test(strippedContent)) return;

      if (requiresSupabaseContent) {
        const hasSupabaseCall = requiresSupabaseContent.some((supaRegex) => supaRegex.test(strippedContent));
        if (!hasSupabaseCall) return;
      }

      if (!mustAlsoContain.test(strippedContent)) {
        violations.push({
          file,
          line: null,
          rule: name,
          description: config.description,
          severity: "BLOCK",
        });
      }
      return;
    }

    // ── SQL RLS & Schema Integrity Check (Specialized) ──
    if (config.type === "sql_rls_integrity" && file.endsWith(".sql")) {
      const sql = content.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--.*$/gm, "");

      // 1. INV-2-RLS-INTEGRITY / INV-DATA-API-GRANT-MISSING: Standard Tables (RLS, Policies, Grants)
      if (name === "INV-2-RLS-INTEGRITY" || name === "INV-DATA-API-GRANT-MISSING") {
        const createTableRegex = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:(\w+)\.)?(\w+)/gi;
        let match;
        while ((match = createTableRegex.exec(sql)) !== null) {
          const schemaName = match[1];
          const tableName = match[2];
          const tableStart = match.index;
          const nextSnippet = sql.substring(tableStart, tableStart + 200);
          if (/PARTITION\s+OF/i.test(nextSnippet)) continue;
          if (schemaName && schemaName.toLowerCase() !== "public") continue;
          
          if (name === "INV-2-RLS-INTEGRITY") {
            // Check RLS
            const rlsRegex = new RegExp(`ALTER\\s+TABLE\\s+(?:public\\.)?${tableName}\\s+ENABLE\\s+ROW\\s+LEVEL\\s+SECURITY`, "i");
            if (!rlsRegex.test(sql)) {
              violations.push({
                file,
                line: null,
                rule: "INV-2-RLS-MANDATORY",
                description: `Table '${tableName}' created but 'ENABLE ROW LEVEL SECURITY' not found in the same file.`,
                severity: "BLOCK"
              });
            } else {
              const policyRegex = new RegExp(`CREATE\\s+POLICY.+ON\\s+(?:public\\.)?${tableName}`, "i");
              if (!policyRegex.test(sql)) {
                if (!getDenyAllTables().has(tableName.toLowerCase()) && !getTablesWithPolicies().has(tableName.toLowerCase())) {
                  violations.push({
                    file,
                    line: null,
                    rule: "INV-2-POLICY-MISSING",
                    description: `Table '${tableName}' has RLS enabled but no policies found.`,
                    severity: "WARN"
                  });
                }
              } else {
                const patternRegex = /\(auth\.jwt\(\)\s*(?:->>\s*'organization_id'|->\s*'app_metadata'\s*->>\s*'org_id')\)::uuid/i;
                if (!patternRegex.test(sql)) {
                  violations.push({
                    file,
                    line: null,
                    rule: "INV-2-ISOLATION-PATTERN",
                    description: `Policy on '${tableName}' might not be using the mandatory VeraProb isolation pattern.`,
                    severity: "WARN"
                  });
                }
              }
            }
          }

          if (name === "INV-DATA-API-GRANT-MISSING") {
            // Check explicit Data API grants
            const grantRegex = new RegExp(`GRANT\\s+.+\\s+ON\\s+(?:TABLE\\s+)?(?:public\\.)?${tableName}\\s+TO\\s+`, "i");
            const hasBypass = new RegExp(`--\\s*INV-DATA-API-GRANT:\\s*(zero-downtime-verified|bypass|internal-only)`, "i").test(content);
            if (!grantRegex.test(sql) && !hasBypass) {
              violations.push({
                file,
                line: null,
                rule: name,
                description: config.description.replace("${tableName}", tableName),
                severity: "BLOCK"
              });
            }
          }
        }
      }

      // 2. PARTITION-RLS-GAP-BLOCK: Partitions (RLS)
      if (name === "PARTITION-RLS-GAP-BLOCK") {
        const createPartitionRegex = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:(\w+)\.)?(\w+)\s+PARTITION\s+OF/gi;
        let partMatch;
        while ((partMatch = createPartitionRegex.exec(sql)) !== null) {
          const partSchema = partMatch[1];
          const partName = partMatch[2];
          if (partSchema && partSchema.toLowerCase() !== "public") continue;
          
          const partRlsRegex = new RegExp(`ALTER\\s+TABLE\\s+(?:public\\.)?${partName}\\s+ENABLE\\s+ROW\\s+LEVEL\\s+SECURITY`, "i");
          if (!partRlsRegex.test(sql)) {
            violations.push({
              file,
              line: null,
              rule: name,
              description: config.description.replace("${partName}", partName),
              severity: "BLOCK"
            });
          }
        }
      }

      // 3. SECURITY-DEFINER-VIEW-BLOCK: Views (security_invoker = true)
      if (name === "SECURITY-DEFINER-VIEW-BLOCK") {
        const createViewRegex = /CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:(\w+)\.)?(\w+)/gi;
        let viewMatch;
        while ((viewMatch = createViewRegex.exec(sql)) !== null) {
          const viewSchema = viewMatch[1];
          const viewName = viewMatch[2];
          if (viewSchema && viewSchema.toLowerCase() !== "public") continue;
          
          const viewStart = viewMatch.index;
          const viewWindow = sql.substring(viewStart, viewStart + 500);
          if (!/WITH\s*\(\s*security_invoker\s*=\s*true\s*\)/i.test(viewWindow)) {
            violations.push({
              file,
              line: null,
              rule: name,
              description: config.description.replace("${viewName}", viewName),
              severity: "BLOCK"
            });
          }
        }
      }

      // 4. ALWAYS-TRUE-RLS-POLICY-BLOCK: permissive USING(true)/WITH CHECK(true)
      //    exposed to a client role. Operates on RAW content so it sees policies
      //    wrapped in EXECUTE $q$...$q$ DO-blocks and the bypass comment.
      if (name === "ALWAYS-TRUE-RLS-POLICY-BLOCK") {
        const policyRegex = /CREATE\s+POLICY\s+(?:"([^"]+)"|([\w]+))/gi;
        let polMatch;
        while ((polMatch = policyRegex.exec(content)) !== null) {
          const policyName = polMatch[1] || polMatch[2];
          const start = polMatch.index;
          // Block ends at the first $q$ (EXECUTE wrapper) or ; after the match.
          const rest = content.slice(start);
          const qIdx = rest.indexOf("$q$");
          const semiIdx = rest.indexOf(";");
          let end = rest.length;
          if (qIdx !== -1) end = Math.min(end, qIdx);
          if (semiIdx !== -1) end = Math.min(end, semiIdx);
          const block = rest.slice(0, end);

          if (/AS\s+RESTRICTIVE/i.test(block)) continue;
          const alwaysTrue =
            /USING\s*\(\s*true\s*\)/i.test(block) ||
            /WITH\s+CHECK\s*\(\s*true\s*\)/i.test(block);
          if (!alwaysTrue) continue;

          // Role scope: a TO clause naming ONLY internal roles is safe; absent
          // TO clause defaults to PUBLIC (unsafe); any client role is unsafe.
          const toMatch = block.match(/\bTO\s+([a-z_,\s]+?)(?:\s+USING|\s+WITH|\s*$)/i);
          if (toMatch) {
            const roles = toMatch[1].split(",").map((r) => r.trim().toLowerCase()).filter(Boolean);
            const internalOnly = roles.length > 0 && roles.every((r) =>
              r === "service_role" || r === "postgres" || r === "supabase_admin");
            if (internalOnly) continue;
          }

          // Bypass: Council-approved comment near the policy.
          const preWindow = content.slice(Math.max(0, start - 300), start);
          if (/pr_scanner:\s*allow-permissive-true-policy/i.test(preWindow + block)) continue;

          violations.push({
            file,
            line: content.slice(0, start).split(/\r?\n/).length,
            rule: name,
            description: config.description.replace("${policyName}", policyName),
            severity: "BLOCK",
          });
        }
      }
      return;
    }

    // ── Line-by-line check ──
    let inFunction = false;
    lines.forEach((line, index) => {
      const trimmedLine = line.trim();
      if (file.endsWith(".sql")) {
        if (/CREATE\s+OR\s+REPLACE\s+FUNCTION/i.test(trimmedLine)) inFunction = true;
        if (inFunction && /\$\$\s*;/i.test(trimmedLine)) {
          inFunction = false;
          return;
        }
      }
      const strippedLine = file.endsWith(".sql")
              ? line.trimEnd().replace(/--.*$/, "").trim()
              : line.trimEnd().replace(/\/\/\/.*$/, "").replace(/\/\/.*$/, "").trim();

      if (!regex.test(strippedLine)) return;
      if (name === "INV-DB" && inFunction) return;

      const hasBypass = bypassKeywords.some((kw) => line.includes(kw)) || (lines[index + 1] && bypassKeywords.some((kw) => lines[index + 1].includes(kw)));
      if (hasBypass) return;

      if (name === "UTC-BLOCK") {
        if (line.includes(".toUtc()") || (lines[index + 1] || "").trim().startsWith(".toUtc()")) return;
      }

      violations.push({
        file,
        line: index + 1,
        rule: name,
        description: config.description,
        severity: config.severity || "BLOCK",
      });
    });
  });
});

// ── Regression Detection (Single Git Call Optimization) ──────────────────────
const { execSync } = require("child_process");

let fileStatuses = new Map();
try {
  const diffOutput = execSync(`git diff --name-status "${baseBranch}"`, { encoding: "utf8" });
  diffOutput.split("\n").forEach(line => {
    const parts = line.trim().split(/\s+/);
    if (parts.length >= 2) {
      const status = parts[0];
      const file = parts[1].replace(/\\/g, "/");
      fileStatuses.set(file, status);
    }
  });
} catch (e) {}

const regressionFiles = changedFiles.filter((file) => {
  const normalizedFile = file.replace(/\\/g, "/");
  if (!normalizedFile.includes("supabase/migrations/") && !normalizedFile.includes("lib/domain/")) return false;
  if (!fs.existsSync(file)) return false;
  const status = fileStatuses.get(normalizedFile);
  if (status && status.startsWith("A")) return false;
  return true;
});

// ── Output ───────────────────────────────────────────────────────────────────

const blocks = violations.filter((v) => v.severity === "BLOCK").length;
const warns = violations.filter((v) => v.severity === "WARN").length;

const result = {
  blocks,
  warns,
  has_regression: regressionFiles.length > 0,
  violations,
  regression_files: regressionFiles,
};

console.log(JSON.stringify(result));
