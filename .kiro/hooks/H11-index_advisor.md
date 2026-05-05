# Hook H-11: Index Advisor (INV-12)

**Trigger**: `preCommit`
**Agent**: Senior Engineer
**Blocking**: No

## Descrição
Sugere a criação de índices SQL baseados nas queries identificadas no código.

## Instruções para o Agente
1. Antes do commit, analise as queries SQL (no Dart ou migrations) usando o advisor:
   ```bash
   python scripts/index_advisor.py
   ```
2. Recomende a criação de índices para melhorar a performance de consultas lentas ou sem índice.

## Validação
- Sugestões de índices apresentadas ao desenvolvedor.
