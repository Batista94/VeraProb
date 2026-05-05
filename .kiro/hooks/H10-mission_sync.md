# Hook H-10: Mission Sync

**Trigger**: `onMissionComplete`
**Agent**: Architect
**Blocking**: No

## Descrição
Sincroniza o estado final do projeto e decisões importantes com o Knowledge Graph.

## Instruções para o Agente
1. Ao finalizar uma tarefa (mission complete), acione a sincronização de memória:
   ```bash
   # Utilizando MCP Memory
   mcp:memory/sync_project_state
   ```
2. Garanta que novas Invariantes ou decisões arquiteturais sejam persistidas para consultas futuras.

## Validação
- Entidades atualizadas no Memory Server.
