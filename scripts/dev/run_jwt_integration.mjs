/**
 * Host runner for jwt_getclaims_integration_test.ts.
 * Loads SUPABASE_URL / SUPABASE_ANON_KEY from env or `supabase status -o env`.
 */
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const functionsDir = join(root, "supabase", "functions");

function parseStatusEnv(stdout) {
  const out = {};
  for (const line of stdout.split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      v = v.slice(1, -1);
    }
    out[m[1]] = v;
  }
  return out;
}

function loadSupabaseEnv() {
  const env = { ...process.env };
  if (env.SUPABASE_URL && env.SUPABASE_ANON_KEY) return env;

  const status = spawnSync("supabase", ["status", "-o", "env"], {
    cwd: root,
    encoding: "utf8",
    shell: true,
  });
  if (status.status !== 0) {
    console.error(
      "[test-jwt-integration] supabase status failed — is Supabase running?",
    );
    console.error(status.stderr || status.stdout);
    process.exit(1);
  }
  const parsed = parseStatusEnv(status.stdout || "");
  env.SUPABASE_URL = env.SUPABASE_URL || parsed.API_URL || "http://127.0.0.1:54321";
  env.SUPABASE_ANON_KEY = env.SUPABASE_ANON_KEY || parsed.ANON_KEY;
  if (!env.SUPABASE_ANON_KEY) {
    console.error("[test-jwt-integration] ANON_KEY missing from supabase status");
    process.exit(1);
  }
  return env;
}

const env = loadSupabaseEnv();
env.REQUIRE_JWT_INTEGRATION = "1";

const result = spawnSync(
  "deno",
  [
    "test",
    "--allow-env",
    "--allow-net",
    "--allow-read",
    "tests/jwt_getclaims_integration_test.ts",
  ],
  { cwd: functionsDir, env, encoding: "utf8", shell: true, stdio: "inherit" },
);

process.exit(result.status ?? 1);
