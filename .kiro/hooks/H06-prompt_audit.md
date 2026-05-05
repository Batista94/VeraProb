# Hook H-06: Prompt Audit (INV-41)

**Trigger**: `preCommit`
**Agent**: QA/Security
**Blocking**: Yes

## Descrição
Protege as instruções do sistema e skills contra ataques de Prompt Injection e Jailbreaks.

## Instruções para o Agente
1. Sempre que houver mudanças em `.kiro/`, `.agents/` ou arquivos `.md` de instrução, acione o auditor:
   ```bash
   # Use a skill configurada via MCP
   skill://prompt-injection-auditor/audit-batch .agents/skills
   ```
2. Analise o relatório de vulnerabilidades.
3. Se houver riscos de injeção detectados, corrija as instruções antes de prosseguir com o commit.

## Validação
- Relatório de auditoria sem vulnerabilidades críticas.
