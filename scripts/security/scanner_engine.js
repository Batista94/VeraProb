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
  if (config.pattern.includes("\n") || config.pattern.includes("\r")) {
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

// ── Scan ─────────────────────────────────────────────────────────────────────

const violations = [];
const bypassKeywords = [
  "// Physical Metric",
  "// pr_scanner: ignore",
    "-- pr_scanner: ignore",
  "- Double Required",
  "Bridge Conversion",
  "Probability Score",
];

changedFiles.forEach((file) => {
  // Skip generated files
  if (file.endsWith(".g.dart") || file.endsWith(".freezed.dart")) return;
  if (!fs.existsSync(file)) return;
  if (!fs.statSync(file).isFile()) return;

  const content = fs.readFileSync(file, "utf8");
  const lines = content.split(/\r?\n/);

  Object.entries(patterns).forEach(([ruleName, config]) => {
    // Path filtering
    if (config.path_filter && !new RegExp(config.path_filter).test(file))
      return;
    if (
      config.exclude_path_pattern &&
      new RegExp(config.exclude_path_pattern, "i").test(file)
    )
      return;
    if (
      config.exclude_files &&
      config.exclude_files.some((exclude) => file.includes(exclude))
    )
      return;
    if (
      config.files_containing &&
      !config.files_containing.some((term) => file.includes(term))
    )
      return;

    function safeRegExp(p) {
      if (!p) return { test: () => true };
      try {
        // Enterprise fix: JSON \b is backspace (0x08). Regex \b is word boundary.
        // We sanitize the pattern to ensure \b always means word boundary.
        const sanitized = String(p).replace(/\x08/g, "\\b");
        return new RegExp(sanitized);
      } catch (e) {
        console.error(`[ERROR] Invalid regex pattern: ${p} (Rule: ${ruleName})`);
        return { test: () => false };
      }
    }
    const regex = safeRegExp(config.pattern);

    // ── Absence Check (INV-1 / INV-26-REPO / INV-30) ──
    if (config.type === "absence_check") {
      const strippedContent = content
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/\/\/\/.*$/gm, "")
        .replace(/\/\/.*$/gm, "");

      if (!regex.test(strippedContent)) return;

      if (config.requires_supabase_content) {
        const hasSupabaseCall = config.requires_supabase_content.some(
          (supaPattern) => safeRegExp(supaPattern).test(strippedContent),
        );
        if (!hasSupabaseCall) return;
      }

      const mustAlsoContain = safeRegExp(config.must_also_contain);
      if (!mustAlsoContain.test(strippedContent)) {
        violations.push({
          file,
          line: null,
          rule: ruleName,
          description: config.description,
          severity: "BLOCK",
        });
      }
      return;
    }

      // ── SQL RLS Integrity Check (INV-2 Specialized) ──
      if (config.type === "sql_rls_integrity" && file.endsWith(".sql")) {
        // File-level bypass: policies superseded by later migrations
        if (content.includes("-- pr_scanner: ignore-rls")) return;
        const sql = content.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--.*$/gm, "");
        
        // Match CREATE TABLE [IF NOT EXISTS] [schema.]name
        const createTableRegex = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:(\w+)\.)?(\w+)/gi;
        let match;
        
        while ((match = createTableRegex.exec(sql)) !== null) {
          const schemaName = match[1]; // undefined if no schema
          const tableName = match[2];
          
          // 0. Ignore partitions (Inherited RLS from parent is sufficient for INV-2)
          const tableStart = match.index;
          const nextSnippet = sql.substring(tableStart, tableStart + 200);
          if (/PARTITION\s+OF/i.test(nextSnippet)) continue;

          // Ignore tables in system schemas (auth, extensions, etc.)
          if (schemaName && schemaName.toLowerCase() !== "public") continue;
          
          // 1. Check ENABLE RLS for THIS specific table
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
            // 2. Check for Policy existence (WARNING)
            const policyRegex = new RegExp(`CREATE\\s+POLICY.+ON\\s+(?:public\\.)?${tableName}`, "i");
            if (!policyRegex.test(sql)) {
              if (!getDenyAllTables().has(tableName.toLowerCase()) && !getTablesWithPolicies().has(tableName.toLowerCase())) {
                violations.push({
                  file,
                  line: null,
                  rule: "INV-2-POLICY-MISSING",
                  description: `Table '${tableName}' has RLS enabled but no policies found. (Warning: Ensure policies are defined or intended to be restrictive).`,
                  severity: "WARN"
                });
              }
            } else {
              // 3. Check for mandatory isolation pattern (WARNING)
              // (auth.jwt() ->> 'organization_id')::uuid
              const patternRegex = /\(auth\.jwt\(\)\s*(?:->>\s*'organization_id'|->\s*'app_metadata'\s*->>\s*'org_id')\)::uuid/i;
              if (!patternRegex.test(sql)) {
                violations.push({
                  file,
                  line: null,
                  rule: "INV-2-ISOLATION-PATTERN",
                  description: `Policy on '${tableName}' might not be using the mandatory VeraProb isolation pattern: (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid`,
                  severity: "WARN"
                });
              }
            }
          }
        }
        return;
      }

      // ── Line-by-line check ──
    // -- Context-Aware Pre-processing for SQL --
    let inFunction = false;
    
    lines.forEach((line, index) => {
      const trimmedLine = line.trim();

      // Track SQL function boundaries to avoid false positives in application logic (INV-DB)
      if (file.endsWith(".sql")) {
        if (/CREATE\s+OR\s+REPLACE\s+FUNCTION/i.test(trimmedLine)) inFunction = true;
        if (inFunction && /\$\$\s*;/i.test(trimmedLine)) {
            inFunction = false;
            return; // Skip the closing line itself
        }
      }

      // Ignore full-line comments and strip end-of-line comments for matching
      // Note: we use trimEnd() to remove \r before stripping comments
      const strippedLine = file.endsWith(".sql")
              ? line.trimEnd().replace(/--.*$/, "").trim()
              : line.trimEnd()
                  .replace(/\/\/\/.*$/, "")
                  .replace(/\/\/.*$/, "")
                  .trim();

      if (!regex.test(strippedLine)) return;

      // Filter out Destructive Operation false positives inside function bodies
      if (ruleName === "INV-DB" && inFunction) return;

      // Bypass check
      const hasBypass =
        bypassKeywords.some((kw) => line.includes(kw)) ||
        (lines[index + 1] &&
          bypassKeywords.some((kw) => lines[index + 1].includes(kw)));
      if (hasBypass) return;

      // UTC special case
      if (ruleName === "UTC-BLOCK") {
        const hasUtcOnSameLine = line.includes(".toUtc()");
        const hasUtcOnNextLine = (lines[index + 1] || "")
          .trim()
          .startsWith(".toUtc()");
        if (hasUtcOnSameLine || hasUtcOnNextLine) return;
      }

      violations.push({
        file,
        line: index + 1,
        rule: ruleName,
        description: config.description,
        severity: config.severity || "BLOCK",
      });
    });
  });
});

// ── Regression Detection ─────────────────────────────────────────────────────
const { execSync } = require("child_process");

const regressionFiles = changedFiles.filter((file) => {
  if (!file.includes("supabase/migrations/") && !file.includes("lib/domain/"))
    return false;
  if (!fs.existsSync(file)) return false;

  // Bypass via comment
  const content = fs.readFileSync(file, "utf8");
  if (content.includes("pr_scanner: ignore-regression") || content.includes("pr_scanner: ignore")) return false;

  // Refinement: New migrations/domain files are evolution, not regression.
  // We check if the file is "Modified" vs "Added" relative to the base branch.
  try {
    const status = execSync(`git diff --name-status "${baseBranch}" -- "${file}"`, { encoding: "utf8" }).trim();
    // If status starts with 'A' (Added), it's not a regression
    if (status.startsWith("A")) return false;
  } catch (e) {
    // If git fails, fallback to safe (flag it)
  }

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
