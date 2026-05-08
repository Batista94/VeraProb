/**
 * analyze_dart_complexity.js — Enterprise Dart Complexity Gate
 *
 * Wraps dart_code_metrics to apply layer-aware thresholds instead of
 * naive line-count heuristics.
 *
 * Metrics checked per function:
 *   - cyclomatic-complexity (decision paths)
 *   - maximum-nesting-level (readability depth)
 *   - lines-of-code (size proxy)
 *
 * Metrics checked per class:
 *   - number-of-methods (god class detection)
 *
 * Thresholds are layer-aware:
 *   domain/application → strictest (business invariants live here)
 *   infrastructure     → moderate
 *   presentation       → lenient (Flutter widget trees are naturally deep)
 *
 * Bypass: add `// pr_scanner: complexity-ok — <reason>` to the file.
 *
 * Usage:
 *   echo "lib/foo.dart\nlib/bar.dart" | node analyze_dart_complexity.js
 *
 * Output (stdout, JSON):
 *   {"blocks":1,"warns":2,"violations":[...],"skipped":false}
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

// ── Thresholds ────────────────────────────────────────────────────────────────

const THRESHOLDS = {
  domain_application: {
    cc_warn: 8,       cc_block: 15,
    nest_warn: 3,     nest_block: 4,
    loc_warn: 40,     loc_block: 80,
    methods_warn: 12, methods_block: 20,
  },
  infrastructure: {
    cc_warn: 10,      cc_block: 18,
    nest_warn: 4,     nest_block: 5,
    loc_warn: 60,     loc_block: 120,
    methods_warn: 18, methods_block: 28,
  },
  presentation: {
    cc_warn: 15,      cc_block: 30,
    nest_warn: 5,     nest_block: 7,
    loc_warn: 100,    loc_block: 200,
    methods_warn: 25, methods_block: 40,
  },
};

function getLayer(filePath) {
  const p = filePath.replace(/\\/g, "/");
  if (/lib\/(domain|application)\//.test(p)) return "domain_application";
  if (/lib\/infrastructure\//.test(p)) return "infrastructure";
  return "presentation";
}

// ── Detect metrics command ────────────────────────────────────────────────────

function detectMetricsCmd() {
  const win = process.platform === "win32";
  const localAppData = process.env.LOCALAPPDATA || "";
  const home = process.env.HOME || process.env.USERPROFILE || "";

  const candidates = win
    ? [
        path.join(localAppData, "Pub", "Cache", "bin", "metrics.bat"),
        path.join(home, "AppData", "Local", "Pub", "Cache", "bin", "metrics.bat"),
        "metrics.bat",
        "metrics",
      ]
    : [
        path.join(home, ".pub-cache", "bin", "metrics"),
        "/usr/local/bin/metrics",
        "metrics",
      ];

  for (const cmd of candidates) {
    try {
      if (fs.existsSync(cmd)) return cmd;
    } catch (_) {}
  }
  return null;
}

// ── Strip ANSI / control characters from metrics stdout ──────────────────────

function cleanOutput(raw) {
  return raw
    .replace(/\x1b\[[^a-zA-Z]*[a-zA-Z]/g, "")
    .replace(/[\x00-\x09\x0b-\x1f\x7f]/g, "")
    .trim();
}

// ── Read changed files from stdin ─────────────────────────────────────────────

const changedFiles = fs
  .readFileSync(0, "utf8")
  .split("\n")
  .map((f) => f.trim())
  .filter(
    (f) =>
      f.length > 0 &&
      f.endsWith(".dart") &&
      !f.endsWith(".g.dart") &&
      !f.endsWith(".freezed.dart")
  );

if (changedFiles.length === 0) {
  console.log(JSON.stringify({ blocks: 0, warns: 0, violations: [], skipped: false }));
  process.exit(0);
}

// ── Find metrics binary ───────────────────────────────────────────────────────

const metricsCmd = detectMetricsCmd();
if (!metricsCmd) {
  console.log(
    JSON.stringify({
      blocks: 0,
      warns: 0,
      violations: [],
      skipped: true,
      warning: "dart_code_metrics binary not found. Install: dart pub global activate dart_code_metrics",
    })
  );
  process.exit(0);
}

// ── Run metrics per unique directory containing changed files ─────────────────

const uniqueDirs = [...new Set(changedFiles.map((f) => path.dirname(f)))].filter(
  (d) => fs.existsSync(d)
);

const allRecords = [];

for (const dir of uniqueDirs) {
  const result = spawnSync(
    metricsCmd,
    ["analyze", dir, "--reporter=json", "--disable-sunset-warning"],
    { encoding: "utf8", maxBuffer: 20 * 1024 * 1024, cwd: process.cwd() }
  );

  const raw = result.stdout || "";
  const cleaned = cleanOutput(raw);
  const jsonStart = cleaned.indexOf("{");
  if (jsonStart === -1) continue;

  try {
    const data = JSON.parse(cleaned.substring(jsonStart));
    allRecords.push(...(data.records || []));
  } catch (_) {
    // malformed output — skip dir
  }
}

// ── Filter to only changed files ──────────────────────────────────────────────

const changedSet = new Set(
  changedFiles.map((f) => f.replace(/\\/g, "/").toLowerCase())
);

const relevantRecords = allRecords.filter((r) =>
  changedSet.has(r.path.replace(/\\/g, "/").toLowerCase())
);

// ── Analyse each record ───────────────────────────────────────────────────────

const violations = [];

for (const record of relevantRecords) {
  const filePath = record.path.replace(/\\/g, "/");

  // File-level bypass
  let content = "";
  try { content = fs.readFileSync(filePath, "utf8"); } catch (_) {}
  if (
    content.includes("pr_scanner: ignore") ||
    content.includes("pr_scanner: complexity-ok")
  )
    continue;

  const t = THRESHOLDS[getLayer(filePath)];

  // ── Class-level: number-of-methods ─────────────────────────────────────────
  for (const [className, classData] of Object.entries(record.classes || {})) {
    const numMethods =
      classData.metrics?.find((m) => m.metricsId === "number-of-methods")
        ?.value ?? 0;

    if (numMethods >= t.methods_block) {
      violations.push({
        file: filePath,
        rule: "GOD-CLASS",
        severity: "BLOCK",
        description: `Class '${className}' has ${numMethods} methods (block ≥ ${t.methods_block}). Extract responsibilities.`,
      });
    } else if (numMethods >= t.methods_warn) {
      violations.push({
        file: filePath,
        rule: "GOD-CLASS",
        severity: "WARN",
        description: `Class '${className}' has ${numMethods} methods (warn ≥ ${t.methods_warn}).`,
      });
    }
  }

  // ── Function-level: CC, nesting, LOC ───────────────────────────────────────
  for (const [fnName, fnData] of Object.entries(record.functions || {})) {
    const m = {};
    for (const entry of fnData.metrics || []) m[entry.metricsId] = entry.value;

    const cc   = m["cyclomatic-complexity"] ?? 1;
    const nest = m["maximum-nesting-level"] ?? 0;
    const loc  = m["lines-of-code"] ?? 0;

    if (cc >= t.cc_block) {
      violations.push({
        file: filePath,
        rule: "HIGH-COMPLEXITY",
        severity: "BLOCK",
        description: `'${fnName}': cyclomatic complexity ${cc} (block ≥ ${t.cc_block}). Decompose into smaller functions.`,
      });
    } else if (cc >= t.cc_warn) {
      violations.push({
        file: filePath,
        rule: "HIGH-COMPLEXITY",
        severity: "WARN",
        description: `'${fnName}': cyclomatic complexity ${cc} (warn ≥ ${t.cc_warn}).`,
      });
    }

    if (nest >= t.nest_block) {
      violations.push({
        file: filePath,
        rule: "DEEP-NESTING",
        severity: "BLOCK",
        description: `'${fnName}': nesting depth ${nest} (block ≥ ${t.nest_block}). Extract guard clauses or sub-functions.`,
      });
    } else if (nest >= t.nest_warn) {
      violations.push({
        file: filePath,
        rule: "DEEP-NESTING",
        severity: "WARN",
        description: `'${fnName}': nesting depth ${nest} (warn ≥ ${t.nest_warn}).`,
      });
    }

    if (loc >= t.loc_block) {
      violations.push({
        file: filePath,
        rule: "LONG-FUNCTION",
        severity: "BLOCK",
        description: `'${fnName}': ${loc} lines (block ≥ ${t.loc_block}). Extract helper methods.`,
      });
    } else if (loc >= t.loc_warn) {
      violations.push({
        file: filePath,
        rule: "LONG-FUNCTION",
        severity: "WARN",
        description: `'${fnName}': ${loc} lines (warn ≥ ${t.loc_warn}).`,
      });
    }
  }
}

// ── Output ────────────────────────────────────────────────────────────────────

const blocks = violations.filter((v) => v.severity === "BLOCK").length;
const warns  = violations.filter((v) => v.severity === "WARN").length;

console.log(JSON.stringify({ blocks, warns, violations, skipped: false }));
