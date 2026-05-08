# Hook H-03: Forensic Scan (Veto Gatekeeper)

**Trigger**: `preCommit`
**Agent**: Lead Reviewer
**Blocking**: Yes (Mandatory for PR/Main)

## Descrição
Executa a auditoria completa de Invariantes e Clean Code antes da integração final.

## Instruções para o Agente
1. Identifique se o commit é para a branch `main` ou se há um PR aberto.
2. Execute o motor de scanner:
   ```bash
   bash scripts/security/pr_full_scanner.sh
   ```
3. Se o veredito for `[NO-GO]`, você deve vetar o commit/merge e listar as violações de Invariantes.
4. Nenhuma violação de Invariante (INV-1 a INV-28) é permitida na branch principal.

## Validação
- Status `[GO]` no relatório gerado pelo scanner.
