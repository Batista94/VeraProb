---
description: Generate pure SQL migrations and enforce manual Supabase execution before allowing Flutter implementation.
---
# 🛠️ Supabase Infrastructure Handoff Skill

**Objective:** Database schemas, RLS policies, and immutable ledgers cannot be trusted to In-Memory tests. Force the PO to apply SQL scripts manually to the remote Supabase instance.

## Instructions
When the user asks for database changes or if your Design Spec requires adding columns/tables:

1. **INVOKE PERSONAS**: Silently read `docs/council/senior_engineer.md` and `docs/council/qa_security.md` to ensure infrastructure realism and security paranoia.
2. **HARD STOP**: Do not write the Flutter/Dart implementations yet.
3. **GENERATE SQL**: Write the full, pure SQL migration block. You must ensure:
   - Tables have `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
   - Every table has an `organization_id UUID NOT NULL REFERENCES organizations(id)`
   - Every table has RLS enabled (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`).
   - Every table has `USING` and `WITH CHECK` policies enforcing `auth.jwt()->>'organization_id'`.
4. **ALERT THE PO**: Output a massive, clear warning in Portuguese:
   > "⚠️ AÇÃO MANUAL REQUERIDA: EXECUTAR NO SUPABASE ⚠️"
   > Cole o script SQL abaixo no SQL Editor do Supabase antes de prosseguirmos.
5. **REQUIRE CONFIRMATION**: Ask explicitly at the end: "Você já executou este SQL com sucesso no Supabase? Responda OK para eu começar o código Dart."

**Do not proceed** to Flutter integration until the user confirms the manual step.