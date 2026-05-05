# Hook H-07: TDD Assist

**Trigger**: `onTestFail`
**Agent**: Senior Engineer
**Blocking**: No

## Descrição
Fornece assistência imediata quando um teste falha, alinhado com a filosofia TDD do projeto.

## Instruções para o Agente
1. Ao detectar uma falha de teste (especialmente `IntegrityException`), analise o stack trace.
2. Sugira a correção mínima necessária para fazer o teste passar (Red -> Green).
3. Não implemente funcionalidades extras além do que o teste exige.

## Validação
- O teste deve passar após a aplicação da sugestão.
