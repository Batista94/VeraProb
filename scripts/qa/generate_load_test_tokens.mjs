#!/usr/bin/env node
// =============================================================================
// veraprob — Phase 8.7: JWT Helper for k6 Multi-Tenant Isolation Test
// =============================================================================
// Fluxo completo:
//   1. Lê URL + chaves do Supabase local (via .env ou `supabase status`)
//   2. Remove registros zombie de auth.users (criados via SQL direta, invisíveis
//      ao GoTrue) usando psql direto no banco local
//   3. Cria usuários de teste via Admin API (GoTrue processa corretamente)
//   4. Garante que user_roles existam (via REST com service_role key)
//   5. Autentica e imprime o bloco de `export` para o k6
//
// PRÉ-REQUISITOS:
//   1. supabase db reset  (migrations + seed.sql → orgs e contracts)
//   2. supabase start     (ou já em execução)
//   3. Node.js >= 18
//
// USO:
//   node scripts/k6_get_test_jwts.mjs
// =============================================================================

import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execSync, spawnSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

// ── Usuários de teste ──────────────────────────────────────────────────────────
const TEST_USERS = [
  {
    id:          '00000000-0000-0000-0000-ffffffffffff',
    email:       'master@veraprob.dev',
    password:    'veraprob123!',
    label:       'SuperAdmin',
    isSuper:     true,
    jwtEnv:      'SUPER_ADMIN_JWT',
  },
  {
    id:          '09d00994-6b32-4df3-b08f-3d722f28f4d0',
    email:       'admin-a@veraprob.dev',
    password:    'veraprob123!',
    org_id:      '00000000-0000-0000-0000-000000000001',
    label:       'Org A',
    jwtEnv:      'ORG_A_JWT',
    orgEnv:      'ORG_A_ID',
    contractId:  '00000000-0000-0000-0000-ca0000000001',
    contractEnv: 'CONTRACT_A_ID',
  },
  {
    id:          '210b892e-2f05-4eff-bb45-c3664141022b',
    email:       'admin-b@veraprob.dev',
    password:    'veraprob123!',
    org_id:      '00000000-0000-0000-0000-000000000002',
    label:       'Org B',
    jwtEnv:      'ORG_B_JWT',
    orgEnv:      'ORG_B_ID',
    contractId:  '00000000-0000-0000-0000-cb0000000001',
    contractEnv: 'CONTRACT_B_ID',
  },
];

// ── Configuração ───────────────────────────────────────────────────────────────

function loadDotEnv() {
  const envPath = join(ROOT, '.env');
  if (!existsSync(envPath)) return {};
  const raw = readFileSync(envPath, 'utf8');
  const vars = {};
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq < 0) continue;
    const key = t.slice(0, eq).trim();
    const val = t.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    if (val) vars[key] = val;
  }
  return vars;
}

function readSupabaseStatus() {
  try {
    const out = execSync('supabase status', { cwd: ROOT, timeout: 10000 }).toString();
    const get = (...labels) => {
      for (const label of labels) {
        const tableMatch = out.match(new RegExp(`│\\s*${label}\\s*│\\s*([^│\\n]+)`));
        if (tableMatch) return tableMatch[1].trim();
        const plainMatch = out.match(new RegExp(`${label}\\s*[:\\|]\\s*([^\\n│]+)`));
        if (plainMatch) return plainMatch[1].trim();
      }
      return null;
    };
    return {
      url:        get('Project URL', 'API URL'),
      anonKey:    get('Publishable', 'anon key'),
      serviceKey: get('Secret', 'service_role key'),
      dbUrl:      get('URL'),  // DB connection URL from ⛁ Database section
    };
  } catch {
    return {};
  }
}

function resolveConfig() {
  const dotenv = loadDotEnv();
  const status = readSupabaseStatus();

  const url = process.env.SUPABASE_URL
    || dotenv['SUPABASE_URL']
    || status.url
    || 'http://127.0.0.1:54321';

  const anonKey = process.env.SUPABASE_ANON_KEY
    || process.env.SUPABASE_KEY
    || dotenv['SUPABASE_ANON_KEY']
    || dotenv['SUPABASE_KEY']
    || status.anonKey
    || '';

  const serviceKey = process.env.SUPABASE_SERVICE_KEY
    || process.env.SERVICE_ROLE_KEY
    || dotenv['SUPABASE_SERVICE_KEY']
    || dotenv['SERVICE_ROLE_KEY']
    || status.serviceKey
    || '';

  // DB URL para psql (porta local padrão do Supabase CLI)
  const dbUrl = status.dbUrl
    || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

  return { url: url.replace(/\/$/, ''), anonKey, serviceKey, dbUrl };
}

// ── Limpeza de registros zombie ────────────────────────────────────────────────
// auth.users inseridos via SQL direta (seed antigo com hash bcrypt ruim ou
// campos faltando) ficam invisíveis ao GoTrue — Admin API retorna 404/500.
// Solução: deletar via CLI local e recriar via Admin API.
function deleteZombieUsers(dbUrl, userIds) {
  const ids = userIds.map(id => `'${id}'`).join(', ');
  const sql = `DELETE FROM auth.users WHERE id IN (${ids});`;

  // Tentativa 1: supabase db execute (CLI 2.x, não precisa de psql no PATH)
  const r1 = spawnSync(
    'supabase', ['db', 'execute', '--local', `--sql=${sql}`],
    { cwd: ROOT, timeout: 15000, encoding: 'utf8' }
  );
  if (r1.status === 0) return { ok: true, deleted: -1 };

  // Tentativa 2: psql no PATH (Unix ou Windows com psql instalado)
  const r2 = spawnSync('psql', [dbUrl, '-c', sql], {
    cwd: ROOT, timeout: 10000, encoding: 'utf8',
  });
  if (r2.status === 0) {
    const count = (r2.stdout || '').match(/DELETE (\d+)/)?.[1] || '0';
    return { ok: true, deleted: parseInt(count) };
  }

  // Tentativa 3: supabase db query (alias em algumas versões do CLI)
  const r3 = spawnSync(
    'supabase', ['db', 'query', '--local', sql],
    { cwd: ROOT, timeout: 15000, encoding: 'utf8' }
  );
  if (r3.status === 0) return { ok: true, deleted: -1 };

  return {
    ok: false,
    sql,
    error: (r1.stderr || r2.stderr || r3.stderr || '').trim(),
  };
}

// ── Helpers HTTP ───────────────────────────────────────────────────────────────

async function apiCall(method, url, headers, body) {
  const opts = { method, headers: { 'Content-Type': 'application/json', ...headers } };
  if (body != null) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  const text = await res.text();
  let data = null;
  try { data = JSON.parse(text); } catch { data = { _raw: text }; }
  return { status: res.status, ok: res.ok, data };
}

// ── Criação de usuário via Admin API ──────────────────────────────────────────
async function createUser(supabaseUrl, serviceKey, user) {
  const headers = {
    'apikey':        serviceKey,
    'Authorization': `Bearer ${serviceKey}`,
  };
  const res = await apiCall('POST', `${supabaseUrl}/auth/v1/admin/users`, headers, {
    id:            user.id,
    email:         user.email,
    password:      user.password,
    email_confirm: true,
    user_metadata: {},
  });

  if (res.status === 200 || res.status === 201) return 'criado';

  // 422 email_exists = usuário já existe (criado em execução anterior) — ok, prosseguir
  if (res.status === 422 && res.data?.error_code === 'email_exists') return 'já existe';

  throw new Error(
    `Admin API retornou HTTP ${res.status} para ${user.email}: ${JSON.stringify(res.data)}`
  );
}

// ── Inserção de user_role via REST (service_role bypassa RLS) ─────────────────
async function ensureUserRole(supabaseUrl, serviceKey, userId, orgId) {
  const res = await apiCall(
    'POST',
    `${supabaseUrl}/rest/v1/user_roles`,
    {
      'apikey':        serviceKey,
      'Authorization': `Bearer ${serviceKey}`,
      'Prefer':        'resolution=ignore-duplicates,return=minimal',
    },
    { user_id: userId, organization_id: orgId, role: 'TENANT_ADMIN' }
  );
  if (res.status === 200 || res.status === 201 || res.status === 204) return;
  throw new Error(
    `Falha ao inserir user_role (user=${userId}): HTTP ${res.status} — ${JSON.stringify(res.data)}`
  );
}

// ── Inserção de super_admin via REST (service_role bypassa RLS) ────────────────
async function ensureSuperRole(supabaseUrl, serviceKey, userId, email) {
  const res = await apiCall(
    'POST',
    `${supabaseUrl}/rest/v1/super_admin_users`,
    {
      'apikey':        serviceKey,
      'Authorization': `Bearer ${serviceKey}`,
      'Prefer':        'resolution=ignore-duplicates,return=minimal',
    },
    { user_id: userId, email: email }
  );
  if (res.status === 200 || res.status === 201 || res.status === 204) return;
  throw new Error(
    `Falha ao inserir super_admin_role (user=${userId}): HTTP ${res.status} — ${JSON.stringify(res.data)}`
  );
}

// ── Sign-in ────────────────────────────────────────────────────────────────────
async function signIn(supabaseUrl, anonKey, email, password) {
  const res = await apiCall(
    'POST',
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    { 'apikey': anonKey },
    { email, password }
  );
  if (res.status !== 200 || !res.data?.access_token) {
    throw new Error(
      `Sign-in falhou para ${email}: HTTP ${res.status} — ${JSON.stringify(res.data)}`
    );
  }
  return res.data.access_token;
}

// ── Main ───────────────────────────────────────────────────────────────────────
async function main() {
  const { url, anonKey, serviceKey, dbUrl } = resolveConfig();

  console.error('\n veraprob — k6 Multi-Tenant Isolation JWT Helper\n');
  console.error(`  Supabase URL  : ${url}`);
  console.error(`  Anon Key      : ${anonKey ? anonKey.slice(0, 24) + '...' : '❌ NÃO ENCONTRADA'}`);
  console.error(`  Service Key   : ${serviceKey ? serviceKey.slice(0, 24) + '...' : '❌ NÃO ENCONTRADA'}`);
  console.error(`  DB URL        : ${dbUrl}`);
  console.error('');

  if (!serviceKey) {
    console.error('  ERRO: service_role key não encontrada.');
    console.error('  Adicione ao .env: SUPABASE_SERVICE_KEY=<valor de `supabase status`>');
    process.exit(1);
  }
  if (!anonKey) {
    console.error('  ERRO: anon key não encontrada.');
    console.error('  Adicione ao .env: SUPABASE_ANON_KEY=<valor de `supabase status`>');
    process.exit(1);
  }

  // ── Passo 0: tentar limpar registros zombie (best-effort — não fatal se comandos indisponíveis)
  process.stderr.write('  [0/3] Limpando registros zombie de auth.users... ');
  const zombieIds = TEST_USERS.map(u => u.id);
  const cleanup = deleteZombieUsers(dbUrl, zombieIds);
  if (cleanup.ok) {
    console.error(cleanup.deleted > 0 ? `${cleanup.deleted} removidos` : 'ok (ou nenhum encontrado)');
  } else {
    // Comandos indisponíveis — continuar e descobrir ao criar se há zombie real
    console.error('aviso: cleanup indisponível, tentando criar diretamente...');
  }
  console.error('');

  const tokens = [];

  for (const user of TEST_USERS) {
    // ── Passo 1: criar usuário via Admin API
    process.stderr.write(`  [1/3] Usuário ${user.label} (${user.email})... `);
    try {
      const result = await createUser(url, serviceKey, user);
      console.error(result);
    } catch (err) {
      console.error('FALHOU');
      // Se é duplicate key (23505), o zombie ainda existe — instruções para resolver
      if (err.message.includes('23505') || err.message.includes('duplicate key')) {
        console.error('\n  ❌ Registro zombie detectado em auth.users (inserido via SQL direta).');
        console.error('\n  SOLUÇÃO: rode no terminal e execute o script novamente:');
        console.error('\n    supabase db reset\n');
      } else {
        console.error(`\n  ERRO: ${err.message}\n`);
      }
      process.exit(1);
    }

    // ── Passo 2: garantir role (Tenant Admin ou SuperAdmin)
    process.stderr.write(`  [2/3] ${user.isSuper ? 'Super role' : 'User role'} ${user.label}... `);
    try {
      if (user.isSuper) {
        await ensureSuperRole(url, serviceKey, user.id, user.email);
      } else {
        await ensureUserRole(url, serviceKey, user.id, user.org_id);
      }
      console.error('ok');
    } catch (err) {
      console.error('FALHOU');
      console.error(`\n  ERRO: ${err.message}`);
      console.error('  Verifique se `supabase db reset` foi executado.\n');
      process.exit(1);
    }

    // ── Passo 3: sign-in para obter JWT com app_metadata injetado pelo hook
    process.stderr.write(`  [3/3] Sign-in ${user.label}... `);
    try {
      const token = await signIn(url, anonKey, user.email, user.password);
      tokens.push({ user, token });
      console.error('ok');
    } catch (err) {
      console.error('FALHOU');
      console.error(`\n  ERRO: ${err.message}\n`);
      process.exit(1);
    }

    console.error('');
  }

  // ── Bloco de export ────────────────────────────────────────────────────────
  const lines = [
    '# ── Copie e cole o bloco abaixo no terminal ────────────────────────────────',
    `export SUPABASE_URL="${url}"`,
    `export SUPABASE_ANON_KEY="${anonKey}"`,
  ];
  for (const { user, token } of tokens)  lines.push(`export ${user.jwtEnv}="${token}"`);
  for (const user of TEST_USERS)         if (user.orgEnv) lines.push(`export ${user.orgEnv}="${user.org_id}"`);
  for (const user of TEST_USERS)         if (user.contractEnv) lines.push(`export ${user.contractEnv}="${user.contractId}"`);
  lines.push('');
  lines.push('# Depois de exportar, rode:');
  lines.push('k6 run scripts/load_test/k6_multi_tenant_isolation.js');
  lines.push('# ─────────────────────────────────────────────────────────────────────────');

  console.log('\n' + lines.join('\n') + '\n');
}

main();
