/**
 * Extract scanner_engine JSON from stdout (tolerates git noise on other lines).
 * Usage: printf '%s' "$raw" | node parse_scan_json.js
 */
const fs = require("fs");

const raw = fs.readFileSync(0, "utf8").trim();
if (!raw) process.exit(1);

try {
  JSON.parse(raw);
  process.stdout.write(raw);
  process.exit(0);
} catch (_) {
  /* fall through */
}

const lines = raw.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
for (let i = lines.length - 1; i >= 0; i--) {
  const line = lines[i];
  if (!line.startsWith("{") || !line.includes('"violations"')) continue;
  try {
    JSON.parse(line);
    process.stdout.write(line);
    process.exit(0);
  } catch (_) {
    /* try previous line */
  }
}

process.exit(1);
