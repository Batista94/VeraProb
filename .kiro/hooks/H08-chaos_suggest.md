# Hook H-08: Chaos Suggest

**Trigger**: `onTestRun`
**Agent**: QA/Security
**Blocking**: No

## Descrição
Sugere cenários de falha e testes de resiliência durante a execução de testes normais.

## Instruções para o Agente
1. Durante a execução de suítes de teste de integração ou telemetria, utilize o simulador de caos:
   ```bash
   skill://iot-chaos-simulator/auto-suggest
   ```
2. Recomende novos casos de teste baseados em latência de rede, falhas de DB ou pacotes corrompidos.
3. Foque em manter a resiliência do sistema em ambientes industriais.

## Validação
- Inclusão de testes de cobertura de cenários de borda/caos.
