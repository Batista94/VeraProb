# Hook H-05: Barrel Scan (INV-13)

**Trigger**: `preCommit`
**Agent**: Architect
**Blocking**: Yes

## Descrição
Valida a integridade dos arquivos Barrel para evitar dependências circulares e vazamentos de domínio.

## Instruções para o Agente
1. Execute o validador:
   ```bash
   python scripts/validate_barrel_files.py
   ```
2. Verifique se as exportações seguem a regra "Anti-Leak" (não exportar implementações internas).
3. Garanta que o core não dependa de camadas superiores através de barrels.

## Validação
- Ausência de ciclos de importação e exportações proibidas.
