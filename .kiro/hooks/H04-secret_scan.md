# Hook H-04: Secret Scan (INV-28)

**Trigger**: `preCommit`
**Agent**: QA/Security
**Blocking**: Yes

## Descrição
Detecta chaves, tokens e segredos acidentalmente incluídos no código.

## Instruções para o Agente
1. Antes de commitar, execute a varredura de segredos:
   ```bash
   python scripts/security/scan_secrets.py
   ```
2. O script analisa a entropia e padrões conhecidos nos arquivos staged.
3. Se detectado, bloqueie o commit e exija a remoção/ofuscação do segredo.
4. Confira o log em `.veraprob/security_audit.log` para detalhes (sem expor o segredo no console).

## Validação
- Zero segredos detectados nos arquivos staged.
