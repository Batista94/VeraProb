# Hook H-02: Type Sync (Dart/SQL Parity)

**Trigger**: `preCommit`
**Agent**: Senior Engineer
**Blocking**: No (Warning mode in dev, Blocking in PR/Main)

## Descrição
Garante que as definições de tipos no Dart estejam em sincronia com o esquema do banco de dados Supabase.

## Instruções para o Agente
1. Sempre que houver mudanças em `supabase/migrations/`, acione a sincronização:
   ```bash
   bash scripts/sync_db_types.sh
   ```
2. Verifique se os arquivos gerados no Dart refletem as novas colunas/tabelas.
3. Informe ao usuário se houver discrepâncias detectadas.

## Validação
- Paridade entre `public.tables` e models Dart.
