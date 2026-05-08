# Hook H-09: Cache Refresh (INV-15)

**Trigger**: `postSave`, `postMerge`
**Agent**: Senior Engineer
**Blocking**: No

## Descrição
Recarrega automaticamente o cache do PostgREST ao detectar mudanças em migrations SQL.

## Instruções para o Agente
1. Ao salvar um arquivo `.sql` em `supabase/migrations/`, ou após um merge que contenha migrations:
   ```bash
   bash scripts/refresh_schema_cache.sh
   ```
2. Garanta que o backend esteja ciente das novas estruturas de tabela imediatamente.

## Validação
- Resposta bem-sucedida do comando de reload do PostgREST.
