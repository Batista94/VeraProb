# Log de Testes: SuperAdmin Management Suite

## Grupo 1: Cadastro de Organizações
- **Status:** PASS (100% de persistência)
- **Observações:**
    - O debounce de CNPJ duplicado está funcional e impediu a criação de duplicatas (CT04).
    - Os convites de admin são gerados automaticamente após a criação da organização.
- **Bugs Identificados:**
    - **BUG-001 (UI/UX):** Instabilidade com caracteres especiais (ç, ã) em campos de texto durante a automação. Recomenda-se revisão do encoding ou do tratamento de strings nos formulários de cadastro.

---
## Grupo 2: Gestão de Administradores
- **Status:** PASS (100% de persistência)
- **Observações:**
    - O sistema de convites permite a revogação instantânea (confirmado via `revoked_at_utc` no DB).
    - A validação de e-mail duplicado em convites pendentes está ativa e retornou `DomainException` como esperado (CT07).
    - O fluxo de UI simplificado solicita apenas o e-mail para o convite, o que difere ligeiramente do plano original mas é funcional.
- **Bugs Identificados:** -

---
## Grupo 3: Edição e Configurações Avançadas
- **Status:** PASS (100% de persistência)
- **Observações:**
    - A atualização de "Viacao Cometa Azul" para "Express" e alteração de parâmetros operacionais (CRM, Custo, Vagas) funcionou perfeitamente (CT10).
    - Toggles de Capabilities (ex: Smart Classify) persistem corretamente com justificativa auditável (CT11).
- **Bugs Identificados:** -

---
## Grupo 4: Ciclo de Vida (Arquivamento)
- **Status:** FAIL
- **Observações:**
    - O fluxo de arquivamento falhou no backend devido a um erro de esquema na RPC `super_admin_archive_organization`.
- **Bugs Identificados:**
    - **BUG-002 (Database):** A RPC `super_admin_archive_organization` tenta acessar a coluna `target_organization_id` na tabela `impersonation_sessions`, mas o nome correto da coluna é `target_org_id`. Isso causa erro 400 ao tentar arquivar qualquer organização.

---
## Grupo 5: Casos de Borda (Edge Cases)
- **Status:** PASS
- **Observações:**
    - Validação de `billing_day` (1-28) impediu valores fora da regra de negócio (CT14).
    - Controle de acesso robusto: Admins pendentes não conseguem logar sem aceitar o convite, prevenindo bypass (CT16).
- **Bugs Identificados:** -

---
## 🏥 Sanity Tests & UAT
- **Status:** PASS
- **Observações:**
    - **ST01/ST02:** Navegação fluida sem erros 500 ou telas vermelhas.
    - **UAT01:** Jornada de onboarding de nova organização "UAT Viacao 2" concluída com geração de token de convite.
- **Bugs Identificados:**
    - **AVISO:** Erro de CORS ao tentar autofill de CNPJ via `receitaws.com.br`. Funcionalidade de apoio inoperante no browser local, mas não bloqueia o fluxo principal.
