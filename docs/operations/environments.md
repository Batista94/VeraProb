# VeraProb — Guia de Ambientes

## Visão Geral

O VeraProb opera com **3 ambientes Supabase isolados**:

| Ambiente | Projeto Supabase | Propósito |
|---|---|---|
| `dev` | `VeraProb-dev` | Desenvolvimento local. Migrations manuais aceitas. |
| `staging` | `VeraProb-staging` | Espelho de prod. Migrations via CI apenas. Dados sintéticos. |
| `prod` | `VeraProb-prod` | Tráfego real. Migrations com aprovação manual. Zero dados de teste. |

> [!CAUTION]
> **Dados de teste NUNCA chegam em prod.** Nenhum `organization_id` de desenvolvimento deve existir em `VeraProb-prod`.

---

## Setup Inicial (Primeiro Acesso)

### 1. Criar os 3 Projetos no Supabase

Acesse [app.supabase.com](https://app.supabase.com) e crie 3 projetos distintos:
- `VeraProb-dev`
- `VeraProb-staging`
- `VeraProb-prod`

Para cada projeto, anote:
- **Project URL** → `Settings → API → Project URL`
- **Anon/Public Key** → `Settings → API → Project API keys → anon public`

### 2. Configurar Ambiente Local (Dev)

```powershell
# Copiar template de variáveis
copy .env.example .env

# Editar com suas credenciais do VeraProb-dev
notepad .env
```

Preencha `SUPABASE_URL` e `SUPABASE_KEY` com as credenciais do projeto **dev**.

### 3. Executar Localmente

```powershell
# Dev (lê .env automaticamente)
flutter run -d chrome

# Ou usar o script de conveniência:
.\scripts\run_dev.ps1

# Staging (via --dart-define, sem .env)
.\scripts\run_staging.ps1
```

---

## Promoção de Migrations

**Regra:** As migrations só promovem em uma direção. Nunca pular um ambiente.

```
dev (SQL Editor Supabase) 
  → commitar arquivo SQL em supabase/migrations/
  → CI valida sintaxe
  → staging (supabase db push automático via CI)
  → prod (supabase db push com aprovação manual)
```

### Promoção Manual (enquanto CI/CD não está configurado)

```powershell
# Instalar Supabase CLI
npm install -g supabase

# Login
supabase login

# Aplicar migrations em staging
supabase db push --project-ref SEU_PROJECT_REF_STAGING

# Aplicar em prod (após validação em staging)
supabase db push --project-ref SEU_PROJECT_REF_PROD
```

---

## Injeção de Credenciais por Ambiente

### Dev (local)
- Credenciais em `.env` (nunca commitado)
- `supabase_client.dart` lê `.env` automaticamente via `flutter_dotenv`

### Staging e Prod (CI/CD)
- Credenciais como **GitHub Actions Secrets**
- Nomes padronizados:

| Secret Name | Descrição | Status |
|---|---|---|
| `SUPABASE_URL_STAGING` | URL do projeto VeraProb-staging | ✅ Cadastrado |
| `SUPABASE_ANON_KEY_STAGING` | Anon key do VeraProb-staging | ✅ Cadastrado |
| `SUPABASE_URL_PROD` | URL do projeto VeraProb-prod | ✅ Cadastrado |
| `SUPABASE_ANON_KEY_PROD` | Anon key do VeraProb-prod | ✅ Cadastrado |
| `SUPABASE_PROJECT_REF_STAGING` | Reference ID do projeto staging (para `supabase db push`) | ⚠️ A cadastrar |
| `SUPABASE_PROJECT_REF_PROD` | Reference ID do projeto prod (para `supabase db push`) | ⚠️ A cadastrar |
| `SUPABASE_ACCESS_TOKEN` | Token de acesso pessoal da Supabase CLI | ⚠️ A cadastrar |
| `SENTRY_DSN_STAGING` | DSN do Sentry para staging | Fase 8.4 |
| `SENTRY_DSN_PROD` | DSN do Sentry para produção | Fase 8.4 |
| `MAPTILER_KEY` | Chave única do MapTiler (compartilhada entre envs) | Fase 8.4 |

> [!NOTE]
> O nome canônico é `SUPABASE_ANON_KEY_*` (com `ANON_KEY`), não `SUPABASE_KEY_*`. Todos os workflows de CI/CD usam este padrão.

### Injeção Manual via --dart-define
```powershell
flutter build web `
  --dart-define=ENV=staging `
  --dart-define=SUPABASE_URL=https://SEU_REF.supabase.co `
  --dart-define=SUPABASE_KEY=eyJ... `
  --dart-define=SENTRY_DSN=https://...
```

> [!CAUTION]
> Nunca interpoler secrets diretamente no `run:` de um GitHub Actions step. Use sempre `env:` para receber o secret e referencie a variável de ambiente no shell (`"$VAR"`). Isso impede que o valor apareça em logs de verbose mode.

---

## Checklist de Verificação de Ambiente

Antes de qualquer deploy em staging ou prod:

- [ ] `.env` foi commitado? → **BLOQUEADOR** — remover do Git imediatamente
- [ ] Migrations foram testadas em dev antes de staging?
- [ ] Dados sintéticos de staging **não chegaram** em prod?
- [ ] `flutter analyze` → 0 erros?
- [ ] `flutter test` → todos passando?

---

## Invariantes Relacionadas

- **INV-6** — Multi-tenant + RLS: cada ambiente tem seu próprio conjunto de `organization_id`s
- **INV-10** — RLS Tenant Claim: `auth.jwt() -> 'app_metadata' ->> 'org_id'` — válido em todos os ambientes
- **CLAUDE.md** — `--dart-define` injetados por ambiente no CI (sem `.env` em pipeline)
