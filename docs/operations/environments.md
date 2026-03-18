# PactaFlow — Guia de Ambientes

## Visão Geral

O PactaFlow opera com **3 ambientes Supabase isolados**:

| Ambiente | Projeto Supabase | Propósito |
|---|---|---|
| `dev` | `PactaFlow-dev` | Desenvolvimento local. Migrations manuais aceitas. |
| `staging` | `PactaFlow-staging` | Espelho de prod. Migrations via CI apenas. Dados sintéticos. |
| `prod` | `PactaFlow-prod` | Tráfego real. Migrations com aprovação manual. Zero dados de teste. |

> [!CAUTION]
> **Dados de teste NUNCA chegam em prod.** Nenhum `organization_id` de desenvolvimento deve existir em `PactaFlow-prod`.

---

## Setup Inicial (Primeiro Acesso)

### 1. Criar os 3 Projetos no Supabase

Acesse [app.supabase.com](https://app.supabase.com) e crie 3 projetos distintos:
- `PactaFlow-dev`
- `PactaFlow-staging`
- `PactaFlow-prod`

Para cada projeto, anote:
- **Project URL** → `Settings → API → Project URL`
- **Anon/Public Key** → `Settings → API → Project API keys → anon public`

### 2. Configurar Ambiente Local (Dev)

```powershell
# Copiar template de variáveis
copy .env.example .env

# Editar com suas credenciais do PactaFlow-dev
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

| Secret Name | Descrição |
|---|---|
| `SUPABASE_URL_STAGING` | URL do projeto PactaFlow-staging |
| `SUPABASE_KEY_STAGING` | Anon key do PactaFlow-staging |
| `SUPABASE_URL_PROD` | URL do projeto PactaFlow-prod |
| `SUPABASE_KEY_PROD` | Anon key do PactaFlow-prod |
| `SENTRY_DSN_STAGING` | DSN do Sentry para staging |
| `SENTRY_DSN_PROD` | DSN do Sentry para produção |
| `MAPTILER_KEY` | Chave única do MapTiler (compartilhada entre envs) |

### Injeção Manual via --dart-define
```powershell
flutter build web `
  --dart-define=ENV=staging `
  --dart-define=SUPABASE_URL=https://SEU_REF.supabase.co `
  --dart-define=SUPABASE_KEY=eyJ... `
  --dart-define=SENTRY_DSN=https://...
```

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
