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
//   node scripts/dev/bootstrap_dev.mjs
// =============================================================================

import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execSync, spawnSync } from 'child_process';
import crypto from 'crypto';


const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..', '..');

// ── Usuários provisionados ─────────────────────────────────────────────────────
const USERS = [
  {
    id: '00000000-0000-0000-0000-ffffffffffff',
    email: 'master@veraprob.dev', // [PUBLIC-TEST-CREDENTIAL]
    password: 'veraprob123!',    // [PUBLIC-TEST-CREDENTIAL]
    label: 'SuperAdmin',
    isSuper: true,
  },
  {
    id: '09d00994-6b32-4df3-b08f-3d722f28f4d0',
    email: 'admin-a@veraprob.dev',
    password: '123456',
    label: 'Admin — Org Alpha',
    org_id: '00000000-0000-0000-0000-000000000001',
    baseRole: 'TENANT_ADMIN',
    tenantRoleName: 'Administrador',
  },
  {
    id: '210b892e-2f05-4eff-bb45-c3664141022b',
    email: 'admin-b@veraprob.dev',
    password: '123456',
    label: 'Admin — Org Beta',
    org_id: '00000000-0000-0000-0000-000000000002',
    baseRole: 'TENANT_ADMIN',
    tenantRoleName: 'Administrador',
  },
  {
    id: '33333333-3333-3333-3333-333333333333',
    email: 'validador@veraprob.dev',
    password: '123456',
    label: 'Validador — Org Alpha',
    org_id: '00000000-0000-0000-0000-000000000001',
    baseRole: 'OPERATOR',
    tenantRoleName: 'Validador',
  },
  {
    id: '44444444-4444-4444-4444-444444444444',
    email: 'auditor@veraprob.dev',
    password: '123456',
    label: 'Auditor — Org Alpha',
    org_id: '00000000-0000-0000-0000-000000000001',
    baseRole: 'AUDITOR',
    tenantRoleName: 'Auditor',
  },
  {
    id: '55555555-5555-5555-5555-555555555555',
    email: 'operador@veraprob.dev',
    password: '123456',
    label: 'Operador — Org Alpha',
    org_id: '00000000-0000-0000-0000-000000000001',
    baseRole: 'OPERATOR',
    tenantRoleName: 'Operador',
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
      url: get('API URL', 'Project URL'),
      anonKey: get('Publishable', 'anon key'),
      serviceKey: get('Secret', 'service_role key'),
    };
  } catch {
    return {};
  }
}

function resolveConfig() {
  const env = loadDotEnv();
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
    || process.env.SUPABASE_SERVICE_ROLE_KEY
    || env['SUPABASE_SERVICE_KEY']
    || env['SUPABASE_SERVICE_ROLE_KEY']
    || env['SERVICE_ROLE_KEY']
    || status.serviceKey
    || '';

  const finalUrl = url.replace(/\/$/, '');

  if (finalUrl.includes(':54323')) {
    console.warn('\x1b[33m  AVISO: SUPABASE_URL parece estar apontando para o Studio (54323).');
    console.warn('         O script de bootstrap precisa do API URL (geralmente :54321).\x1b[0m\n');
  }

  return { url: finalUrl, anonKey, serviceKey };
}

// ── Helpers HTTP ───────────────────────────────────────────────────────────────

async function post(url, headers, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { _raw: text }; }
  return { status: res.status, ok: res.ok, data };
}

async function patch(url, headers, body) {
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { _raw: text }; }
  return { status: res.status, ok: res.ok, data };
}

async function put(url, headers, body) {
  const res = await fetch(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
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
  const res = await post(
    `${url}/rest/v1/super_admin_users`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    { user_id: user.id, email: user.email },
  );

  if (res.status !== 200 && res.status !== 201 && res.status !== 204 && res.status !== 409) {
    throw new Error(`HTTP ${res.status}: ${JSON.stringify(res.data)}`);
  }

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
  const baseRole = user.baseRole || 'TENANT_ADMIN';
  const res = await post(
    `${url}/rest/v1/user_roles`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    { user_id: user.id, organization_id: user.org_id, role: baseRole, is_active: true },
  );
  if (res.status === 200 || res.status === 201 || res.status === 204 || res.status === 409) {
    // Sync raw_app_meta_data so getCurrentUser() (which reads user.appMetadata)
    // also resolves org_id without relying solely on the JWT hook claims.
    const res2 = await put(
      `${url}/auth/v1/admin/users/${user.id}`,
      authHeaders(serviceKey),
      { app_metadata: { org_id: user.org_id, role: baseRole } },
    );
    if (!res2.ok) {
      throw new Error(`app_metadata update failed: HTTP ${res2.status}: ${JSON.stringify(res2.data)}`);
    }

    // Now, assign the specific tenant_role if requested
    if (user.tenantRoleName) {
      const resRole = await fetch(
        `${url}/rest/v1/tenant_roles?organization_id=eq.${user.org_id}&name=eq.${encodeURIComponent(user.tenantRoleName)}&select=id`,
        { headers: authHeaders(serviceKey) }
      );
      const roles = await resRole.json();
      if (roles && roles.length > 0) {
        const roleId = roles[0].id;
        const resAssign = await post(
          `${url}/rest/v1/user_tenant_roles`,
          { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
          { user_id: user.id, tenant_role_id: roleId, organization_id: user.org_id }
        );
        if (![200, 201, 204, 409].includes(resAssign.status)) {
          throw new Error(`HTTP ${resAssign.status} (assign): ${JSON.stringify(resAssign.data)}`);
        }
      } else {
        console.log(`\n  AVISO: tenant_role '${user.tenantRoleName}' não encontrado na Org ${user.org_id}`);
      }
    }
    return;
  }
  throw new Error(`HTTP ${res.status}: ${JSON.stringify(res.data)}`);
}

// ── Enriquecer Organizações do Seed com dados completos ───────────────────────

async function enrichSeedOrganizations(url, serviceKey) {
  process.stdout.write('  ── Enriquecendo Organizações do Seed (campos obrigatórios)\n');

  const orgUpdates = [
    {
      id: '00000000-0000-0000-0000-000000000001',
      data: {
        legal_name: 'Alpha Transportes e Logística Ltda',
        cnpj: '78.423.287/0001-50',
        plan_type: 'professional',
        max_vehicles: 80,
        max_active_contracts: 15,
        billing_day: 10,
        contact_email: 'financeiro@alpha-transportes.com.br',
        external_id: 'CRM-ALPHA-001',
        tool_cost_cents: 500000,
        dwell_time_seconds: 300,
        organization_type: 'CARGO',
        timezone: 'America/Sao_Paulo',
        currency_code: 'BRL',
        allowed_domains: ['alpha-transportes.com.br', 'veraprob.dev'],
        capabilities: {
          allows_sealing: true,
          allows_loading: true,
          allows_cargo_check: true,
          allows_incident: true,
          allows_doc: true,
          smart_classify: true,
        },
      },
    },
    {
      id: '00000000-0000-0000-0000-000000000002',
      data: {
        legal_name: 'Beta Viação e Turismo S.A.',
        cnpj: '29.653.604/0001-19',
        plan_type: 'starter',
        max_vehicles: 30,
        max_active_contracts: 5,
        billing_day: 15,
        contact_email: 'contato@beta-viacao.com.br',
        external_id: 'CRM-BETA-002',
        tool_cost_cents: 250000,
        dwell_time_seconds: 300,
        organization_type: 'PASSENGER',
        timezone: 'America/Sao_Paulo',
        currency_code: 'BRL',
        allowed_domains: ['beta-viacao.com.br', 'veraprob.dev'],
        capabilities: {
          allows_sealing: false,
          allows_loading: false,
          allows_cargo_check: false,
          allows_incident: true,
          allows_doc: true,
          smart_classify: false,
        },
      },
    },
  ];

  for (const org of orgUpdates) {
    process.stdout.write(`      Org ${org.id.slice(-1)}... `);
    const res = await patch(
      `${url}/rest/v1/organizations?id=eq.${org.id}`,
      { ...authHeaders(serviceKey), Prefer: 'return=minimal' },
      org.data,
    );
    if (res.ok) {
      console.log('ok');
    } else {
      console.log(`AVISO (${res.status}): ${JSON.stringify(res.data).slice(0, 120)}`);
    }
  }
  console.log('');
}

// ── Dados de Teste (Motorista, Telegram, Viagem) ──────────────────────────────

async function ensureTestData(url, serviceKey) {
  process.stdout.write('  ── Provisionando Dados de Teste (Motorista + Token Telegram)\n');

  const driverId = '00000000-0000-0000-0000-d00000000001';
  const orgId = '00000000-0000-0000-0000-000000000001';

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
  if (!resDriver.ok && resDriver.status !== 409) throw new Error(`Erro ao criar motorista: ${resDriver.status}`);
  console.log('ok');

  // 2. Criar Token de Vinculação
  process.stdout.write('      [2/4] Gerar token VERAPR22... ');
  const resToken = await post(
    `${url}/rest/v1/telegram_binding_tokens`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=representation' },
    {
      organization_id: orgId,
      driver_id: driverId,
      created_by_user_id: '00000000-0000-0000-0000-ffffffffffff',
      code: 'VERAPR22',
      expires_at_utc: new Date(Date.now() + 14 * 60 * 1000).toISOString()
    }
  );

  if (!resToken.ok && resToken.status !== 409) {
    console.log('FALHOU');
    throw new Error(`Erro ao criar token: ${resToken.status} - ${JSON.stringify(resToken.data)}`);
  }

  let tokenId = resToken.data?.[0]?.id;
  if (!tokenId) {
    const resGetToken = await fetch(`${url}/rest/v1/telegram_binding_tokens?code=eq.VERAPR22&select=id`, {
      headers: authHeaders(serviceKey)
    });
    const tokens = await resGetToken.json();
    tokenId = tokens[0]?.id;
  }
  console.log('ok');

  // 3. Pré-vincular Chat Telegram (Dev-Mode)
  const TEST_CHAT_ID = 908453789;
  process.stdout.write(`      [3/4] Pré-vincular Chat ID ${TEST_CHAT_ID}... `);
  const resBind = await post(
    `${url}/rest/v1/telegram_chat_bindings`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    {
      organization_id: orgId,
      driver_id: driverId,
      chat_id: TEST_CHAT_ID,
      binding_token_id: tokenId
    }
  );
  if (!resBind.ok && resBind.status !== 409) throw new Error(`Erro ao pré-vincular: ${resBind.status} - ${JSON.stringify(resBind.data)}`);
  console.log('ok');

  // 4. Criar Viagem de Teste (TRIP-8H-TEST) para Heurística WS-4
  process.stdout.write('      [4/4] Criar Viagem TRIP-8H-TEST (8h)... ');
  const now = new Date();
  const start = new Date(now.getTime() - 5 * 60 * 1000).toISOString();
  const end = new Date(now.getTime() + 8 * 60 * 60 * 1000 - 5 * 60 * 1000).toISOString();
  const contractId = '00000000-0000-0000-0000-ca0000000001';
  const planId = '00000000-0000-0000-0000-000000000001';
  const setId = 'TRIP-8H-TEST';

  // 4.1 Plan Declaration (com organization_id!)
  await post(
    `${url}/rest/v1/plan_declarations`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    {
      id: planId,
      contract_id: contractId,
      organization_id: orgId,
      declared_at_utc: now.toISOString(),
      declared_by_user_id: '00000000-0000-0000-0000-ffffffffffff',
      plan_version: 1,
      original_file_hash: 'bootstrap'
    }
  );

  // 4.2 Service Execution
  await post(
    `${url}/rest/v1/contractual_service_executions`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    {
      set_id: setId,
      plan_declaration_id: planId,
      scheduled_start_time_utc: start,
      scheduled_end_time_utc: end,
      planned_vehicle_id: driverId,
      contractual_value_cents: 25000,
      no_show_penalty_multiplier: 1.5,
      start_latitude: -23.55, start_longitude: -46.63, start_radius_meters: 500,
      end_latitude: -23.6, end_longitude: -46.7, end_radius_meters: 500
    }
  );

  // 4.3 Execution State (pending)
  await post(
    `${url}/rest/v1/execution_states`,
    { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
    {
      id: '00000000-0000-0000-0000-e00000000001',
      set_id: setId,
      contract_id: contractId,
      plan_version: 1,
      planned_vehicle_id: driverId,
      status: 'pending',
      window_start_utc: start,
      window_end_utc: end,
      contractual_value_cents: 25000,
      no_show_penalty_multiplier: 1.5,
      created_at_utc: now.toISOString(),
      last_evaluated_at_utc: now.toISOString(),
      status_last_updated_at_utc: now.toISOString(),
      start_latitude: -23.55, start_longitude: -46.63, start_radius_meters: 500
    }
  );
  console.log('ok');

  // 5. Cenários Avançados (INV-6 Backdating + Anti-Flood)
  await ensureAntiFloodScenario(url, serviceKey, orgId);
  await ensureBackdatingScenarios(url, serviceKey, orgId, planId, driverId);

  console.log('');
}

async function ensureAntiFloodScenario(url, serviceKey, orgId) {
  process.stdout.write('      [5.1] Cenário Anti-Flood (Alertas)... ');
  const alerts = Array.from({ length: 5 }, (_, i) => ({
    organization_id: orgId,
    entity_id: '999999999',
    alert_type: 'TELEGRAM_ORPHAN',
    severity: 'CRITICAL',
    status: 'ACTIVE',
    source: 'telegram',
    triggering_event_id: crypto.randomUUID(),
    context: { iteration: i, note: 'Teste de supressão de flood' }
  }));

  for (const alert of alerts) {
    await post(`${url}/rest/v1/operational_alerts`, { ...authHeaders(serviceKey) }, alert);
  }
  console.log('ok');
}

async function ensureBackdatingScenarios(url, serviceKey, orgId, planId, driverId) {
  process.stdout.write('      [5.2] Cenários Backdating (INV-6)... ');
  const now = new Date();

  const scenarios = [
    { id: 'BDT-SET-01', note: '10 min ago (Closed)' },
    { id: 'BDT-SET-02', note: 'NULL fallback (Pending)' },
    { id: 'BDT-SET-05', note: 'Pre-set entered_at (CAS)' }
  ];

  for (const sc of scenarios) {
    await post(
      `${url}/rest/v1/contractual_service_executions`,
      { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
      {
        set_id: sc.id,
        plan_declaration_id: planId,
        scheduled_start_time_utc: now.toISOString(),
        scheduled_end_time_utc: new Date(now.getTime() + 4 * 60 * 60 * 1000).toISOString(),
        planned_vehicle_id: driverId,
        start_latitude: 0, start_longitude: 0, start_radius_meters: 500,
        end_latitude: 0, end_longitude: 0, end_radius_meters: 500
      }
    );

    await post(
      `${url}/rest/v1/execution_states`,
      { ...authHeaders(serviceKey), Prefer: 'resolution=ignore-duplicates,return=minimal' },
      {
        set_id: sc.id,
        organization_id: orgId,
        contract_id: 'BDT-CONTRACT',
        status: 'inTransit',
        window_start_utc: now.toISOString(),
        window_end_utc: new Date(now.getTime() + 4 * 60 * 60 * 1000).toISOString(),
        destination_zone_entered_at_utc: sc.id === 'BDT-SET-05' ? '2000-01-01T10:00:00Z' : null
      }
    );
  }
  console.log('ok');
}



// ── Sign-in helper ────────────────────────────────────────────────────────────

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
  const ids = userIds.map(id => `'${id}'`).join(', ');
  const sql = `
    DELETE FROM auth.users WHERE id IN (${ids});
    DELETE FROM public.super_admin_users WHERE user_id IN (${ids});
    DELETE FROM public.user_roles WHERE user_id IN (${ids});
  `.replace(/\s+/g, ' ').trim();

  const opts = { cwd: ROOT, timeout: 15000, encoding: 'utf8', shell: true };
  try {
    const r = spawnSync('supabase', ['db', 'execute', '--local', `--sql=${sql}`], opts);
    return r.status === 0;
  } catch {
    return false;
  }
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
      console.error('  Tente: supabase db reset && node scripts/dev/bootstrap_dev.mjs\n');
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

  // Enriquecer orgs do seed com dados completos
  await enrichSeedOrganizations(url, serviceKey);

  // Dados de negócio
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
  console.log('    flutter run --dart-define=SKIP_MFA_DEV=true');
  console.log('');
}

main();
