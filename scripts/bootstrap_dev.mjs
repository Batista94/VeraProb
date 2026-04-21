#!/usr/bin/env node
// =============================================================================
// VeraProb — Dev Environment Bootstrap
// =============================================================================
// Propósito: Criar todos os usuários de teste após `supabase db reset`.
//            Use este script para testes manuais e desenvolvimento.
//            Para gerar JWTs para o k6, use: node scripts/k6_get_test_jwts.mjs
//
// PRÉ-REQUISITOS:
//   1. supabase db reset   (migrations + seed.sql aplicados)
//   2. supabase start      (serviço já em execução)
//   3. Node.js >= 18
//
// USO:
//   node scripts/bootstrap_dev.mjs
// =============================================================================

import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execSync, spawnSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

// ── Usuários provisionados ─────────────────────────────────────────────────────
const USERS = [
  {
    id:       '00000000-0000-0000-0000-ffffffffffff',
    email:    'master@veraprob.dev',
    password: 'veraprob123!',
    label:    'SuperAdmin',
    isSuper:  true,
  },
  {
    id:       '09d00994-6b32-4df3-b08f-3d722f28f4d0',
    email:    'admin-a@veraprob.dev',
    password: 'veraprob123!',
    label:    'Admin — Org Alpha',
    org_id:   '00000000-0000-0000-0000-000000000001',
  },
  {
    id:       '210b892e-2f05-4eff-bb45-c3664141022b',
    email:    'admin-b@veraprob.dev',
    password: 'veraprob123!',
    label:    'Admin — Org Beta',
    org_id:   '00000000-0000-0000-0000-000000000002',
  },
];

// ── Configuração ───────────────────────────────────────────────────────────────

function loadDotEnv() {
  for (const name of ['.env.development', '.env']) {
    const p = join(ROOT, name);
    if (!existsSync(p)) continue;
    const vars = {};
    for (const line of readFileSync(p, 'utf8').split('\n')) {
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
  return {};
}

function readSupabaseStatus() {
  try {
    const out = execSync('supabase status', { cwd: ROOT, timeout: 10000 }).toString();
    const get = (...labels) => {
      for (const label of labels) {
        const m1 = out.match(new RegExp(`│\\s*${label}\\s*│\\s*([^│\\n]+)`));
        if (m1) return m1[1].trim();
        const m2 = out.match(new RegExp(`${label}\\s*[:\\|]\\s*([^\\n│]+)`));
        if (m2) return m2[1].trim();
      }
      return null;
    };
    return {
      url:        get('API URL', 'Project URL'),
      anonKey:    get('Publishable', 'anon key'),
      serviceKey: get('Secret', 'service_role key'),
    };
  } catch {
    return {};
  }
}

function resolveConfig() {
  const env    = loadDotEnv();
  const status = readSupabaseStatus();

  const url = process.env.SUPABASE_URL
    || env['SUPABASE_URL']
    || status.url
    || 'http://127.0.0.1:54321';

  const anonKey = process.env.SUPABASE_ANON_KEY
    || env['SUPABASE_ANON_KEY']
    || env['SUPABASE_KEY']
    || status.anonKey
    || '';

  const serviceKey = process.env.SUPABASE_SERVICE_KEY
    || env['SUPABASE_SERVICE_KEY']
    || env['SERVICE_ROLE_KEY']
    || status.serviceKey
    || '';

  const finalUrl = url.replace(/\/$/, '');

  // Safety check: common mistake is pointing to Studio (54323) instead of API (54321)
  if (finalUrl.includes(':54323')) {
    console.warn('\x1b[33m  AVISO: SUPABASE_URL parece estar apontando para o Studio (54323).');
    console.warn('         O script de bootstrap precisa do API URL (geralmente :54321).\x1b[0m\n');
  }

  return { url: finalUrl, anonKey, serviceKey };
}

// ── Helpers HTTP ───────────────────────────────────────────────────────────────

async function post(url, headers, body) {
  const res = await fetch(url, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body:    JSON.stringify(body),
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { _raw: text }; }
  return { status: res.status, ok: res.ok, data };
}

async function patch(url, headers, body) {
  const res = await fetch(url, {
    method:  'PATCH',
    headers: { 'Content-Type': 'application/json', ...headers },
    body:    JSON.stringify(body),
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { _raw: text }; }
  return { status: res.status, ok: res.ok, data };
}

async function put(url, headers, body) {
  const res = await fetch(url, {
    method:  'PUT',
    headers: { 'Content-Type': 'application/json', ...headers },
    body:    JSON.stringify(body),
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { _raw: text }; }
  return { status: res.status, ok: res.ok, data };
}

function authHeaders(key) {
  return { apikey: key, Authorization: `Bearer ${key}` };
}

// ── Operações ─────────────────────────────────────────────────────────────────

async function createAuthUser(url, serviceKey, user) {
  const res = await post(`${url}/auth/v1/admin/users`, authHeaders(serviceKey), {
    id: user.id, email: user.email, password: user.password, email_confirm: true,
  });
  if (res.ok) return 'criado';
  if (res.status === 422 && res.data?.error_code === 'email_exists') return 'já existe';
  throw new Error(`HTTP ${res.status}: ${JSON.stringify(res.data)}`);
}

async function ensureSuperAdmin(url, serviceKey, user) {
  // 1. Insert into super_admin_users (triggers JWT hook for future tokens).
  const res = await post(
    `${url}/rest/v1/super_admin_users`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    { user_id: user.id, email: user.email },
  );
  if (res.status !== 200 && res.status !== 201 && res.status !== 204) {
    throw new Error(`HTTP ${res.status}: ${JSON.stringify(res.data)}`);
  }

  // 2. Persist super_admin=true to raw_app_meta_data so Edge Function's
  //    getUser() sees the flag (JWT hook only enriches the token, not the DB row).
  //    NOTE: GoTrue Admin API uses PUT for user updates (INV-14).
  const res2 = await put(
    `${url}/auth/v1/admin/users/${user.id}`,
    authHeaders(serviceKey),
    { app_metadata: { super_admin: true } },
  );
  if (!res2.ok) {
    throw new Error(`app_metadata update failed: HTTP ${res2.status}: ${JSON.stringify(res2.data)}`);
  }
}

async function ensureTenantAdmin(url, serviceKey, user) {
  const res = await post(
    `${url}/rest/v1/user_roles`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    { user_id: user.id, organization_id: user.org_id, role: 'TENANT_ADMIN' },
  );
  if (res.status === 200 || res.status === 201 || res.status === 204) return;
  throw new Error(`HTTP ${res.status}: ${JSON.stringify(res.data)}`);
}

async function ensureTestData(url, serviceKey) {
  process.stdout.write('  ── Provisionando Dados de Teste (Motorista + Token Telegram)\n');

  const driverId = '00000000-0000-0000-0000-d00000000001';
  const orgId    = '00000000-0000-0000-0000-000000000001';

  // 1. Criar Motorista
  process.stdout.write('      [1/2] Criar motorista de teste... ');
  const resDriver = await post(
    `${url}/rest/v1/drivers`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    { 
      id: driverId, 
      organization_id: orgId, 
      full_name: 'Motorista de Teste Telegram', 
      status: 'active',
      license_number: 'CNH123456789'
    }
  );
  if (!resDriver.ok) throw new Error(`Erro ao criar motorista: ${resDriver.status}`);
  console.log('ok');

  // 2. Criar Token de Vinculação
  process.stdout.write('      [2/2] Gerar token VERAPR22... ');
  const resToken = await post(
    `${url}/rest/v1/telegram_binding_tokens`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    {
      organization_id: orgId,
      driver_id: driverId,
      created_by_user_id: '00000000-0000-0000-0000-ffffffffffff',
      code: 'VERAPR22',
      expires_at_utc: new Date(Date.now() + 15 * 60 * 1000).toISOString() // Máximo de 15 min permitido pelo banco
    }
  );
  if (!resToken.ok) throw new Error(`Erro ao criar token: ${resToken.status}`);
  console.log('ok\n');
}

async function signIn(url, anonKey, email, password) {
  const res = await post(
    `${url}/auth/v1/token?grant_type=password`,
    { apikey: anonKey },
    { email, password },
  );
  if (res.ok && res.data?.access_token) return res.data.access_token;
  throw new Error(`HTTP ${res.status}: ${JSON.stringify(res.data)}`);
}

function cleanupZombies(userIds) {
  const ids  = userIds.map(id => `'${id}'`).join(', ');
  const sql  = `DELETE FROM auth.users WHERE id IN (${ids});`;
  const opts = { cwd: ROOT, timeout: 15000, encoding: 'utf8' };
  const r    = spawnSync('supabase', ['db', 'execute', '--local', `--sql=${sql}`], opts);
  return r.status === 0;
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  const { url, anonKey, serviceKey } = resolveConfig();

  console.log('\n╔══════════════════════════════════════════════════════════╗');
  console.log('║          VeraProb — Dev Environment Bootstrap           ║');
  console.log('╚══════════════════════════════════════════════════════════╝\n');
  console.log(`  URL:         ${url}`);
  console.log(`  Anon Key:    ${anonKey ? anonKey.slice(0, 20) + '...' : '❌ NÃO ENCONTRADA'}`);
  console.log(`  Service Key: ${serviceKey ? serviceKey.slice(0, 20) + '...' : '❌ NÃO ENCONTRADA'}`);
  console.log('');

  if (!serviceKey || !anonKey) {
    console.error('  ERRO: chaves não encontradas.');
    console.error('  Execute `supabase status` e adicione ao .env.development:');
    console.error('    SUPABASE_URL=http://127.0.0.1:54321');
    console.error('    SUPABASE_ANON_KEY=<anon key>');
    console.error('    SUPABASE_SERVICE_KEY=<service_role key>');
    process.exit(1);
  }

  // Limpar auth.users zombies (best-effort)
  process.stdout.write('  [pré] Limpando usuários residuais... ');
  const cleaned = cleanupZombies(USERS.map(u => u.id));
  console.log(cleaned ? 'ok' : 'ignorado (CLI indisponível)');
  console.log('');

  const results = [];

  for (const user of USERS) {
    console.log(`  ── ${user.label} (${user.email})`);

    process.stdout.write('      [1/3] Criar auth.users... ');
    try {
      const r = await createAuthUser(url, serviceKey, user);
      console.log(r);
    } catch (e) {
      console.log('FALHOU');
      console.error(`\n  ERRO: ${e.message}`);
      console.error('  Tente: supabase db reset && node scripts/bootstrap_dev.mjs\n');
      process.exit(1);
    }

    process.stdout.write('      [2/3] Atribuir role + app_metadata... ');
    try {
      if (user.isSuper) {
        await ensureSuperAdmin(url, serviceKey, user);
      } else {
        await ensureTenantAdmin(url, serviceKey, user);
      }
      console.log('ok');
    } catch (e) {
      console.log('FALHOU');
      console.error(`\n  ERRO: ${e.message}\n`);
      process.exit(1);
    }

    process.stdout.write('      [3/3] Verificar login... ');
    try {
      await signIn(url, anonKey, user.email, user.password);
      console.log('ok');
    } catch (e) {
      console.log('FALHOU');
      console.error(`\n  ERRO: ${e.message}\n`);
      process.exit(1);
    }

    results.push(user);
    console.log('');
  }

  // Novo: Dados de negócio
  await ensureTestData(url, serviceKey);

  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║                  CREDENCIAIS DE TESTE                   ║');
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  for (const u of results) {
    console.log(`  ${u.label}`);
    console.log(`    Email:  ${u.email}`);
    console.log(`    Senha:  ${u.password}`);
    if (u.org_id) console.log(`    Org ID: ${u.org_id}`);
    console.log('');
  }

  console.log('  ATENÇÃO (SI): Credenciais acima são exclusivas para');
  console.log('  ambiente local de desenvolvimento. Nunca use em produção.');
  console.log('');
  console.log('  Inicie o app:');
  console.log('    flutter run -d chrome');
  console.log('');
}

main();
