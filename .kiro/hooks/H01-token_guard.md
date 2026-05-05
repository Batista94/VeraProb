# Hook H-01: Token Guard (INV-40)

**Trigger**: `preToolUse`
**Agent**: All (*)
**Blocking**: Yes

## Descrição
Monitora e bloqueia chamadas de ferramentas que excedam o limite de tokens ou acessem diretórios proibidos (como `node_modules`).

## Instruções para o Agente
1. Antes de executar qualquer ferramenta, verifique se o input é excessivamente longo (>800 chars).
2. Execute o script de validação:
   ```bash
   bash .kiro/scripts/pre-tool-use.sh
   ```
3. Se o script retornar erro, aborte a execução da ferramenta e informe o usuário sobre a violação da INV-40.
4. Garanta que arquivos ignorados pelo `.claudeignore` não sejam lidos.

## Validação
- O script deve retornar status 0 para prosseguir.
