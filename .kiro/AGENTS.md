# Protocolo de Consciência Coletiva (VeraProb Council)

## 1. HIERARQUIA DE CONTEXTO
1.  **PERSONAS (.claude/agents/)**: A lógica base e o tom de voz. São os "Prompts Mestres".
2.  **MANIFESTOS (.kiro/agents/)**: A configuração ativa. Definem quais ferramentas e dogmas cada persona carrega para a missão atual.
3.  **DOGMA (.kiro/steering/)**: As Invariantes INV-1 a INV-28. São injetadas automaticamente em todos os agentes.

## 2. FLUXO DE CONSENSO
Nenhuma alteração de código é aceita sem o **Veredito Triplo**:
1.  **Deterministic Pass**: Sucesso no `pr_full_scanner.sh` (Saída 0).
2.  **Neural Review**: Aprovação do `Lead Reviewer` contra as Invariantes.
3.  **Security Audit**: Assinatura do `QA/Security` validando que não há riscos de injeção ou vazamento de tenant.

## 3. ESTADO DA MISSÃO
As `specs/` são a única fonte de verdade para o progresso. Se uma task não está no `tasks.md`, ela não existe no backlog da IA.
