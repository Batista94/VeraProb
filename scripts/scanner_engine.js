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

// ── Read Changed Files from stdin ────────────────────────────────────────────

const changedFiles = fs
  .readFileSync(0, "utf8")
  .split("\n")
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

// ── Scan ─────────────────────────────────────────────────────────────────────

const violations = [];
const bypassKeywords = [
  "// Physical Metric",
  "// pr_scanner: ignore",
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
  const lines = content.split("\n");

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

    const regex = new RegExp(config.pattern);

    // ── Absence Check (INV-1 / INV-26-REPO / INV-30) ──
    if (config.type === "absence_check") {
      const strippedContent = content
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/\/\/\/.*$/gm, "")
        .replace(/\/\/.*$/gm, "");

      if (!regex.test(strippedContent)) return;

      if (config.requires_supabase_content) {
        const hasSupabaseCall = config.requires_supabase_content.some(
          (supaPattern) => new RegExp(supaPattern).test(strippedContent),
        );
        if (!hasSupabaseCall) return;
      }

      const mustAlsoContain = new RegExp(config.must_also_contain);
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

    // ── Line-by-line check ──
    lines.forEach((line, index) => {
      // Ignore full-line comments and strip end-of-line comments for matching
      const strippedLine = line
        .replace(/\/\/\/.*$/, "")
        .replace(/\/\/.*$/, "")
        .trim();

      if (!regex.test(strippedLine)) return;

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

const regressionFiles = changedFiles.filter((file) => {
  if (!file.includes("supabase/migrations/") && !file.includes("lib/domain/"))
    return false;
  if (!fs.existsSync(file)) return false;
  const content = fs.readFileSync(file, "utf8");
  return !content.includes("pr_scanner: ignore-regression");
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
