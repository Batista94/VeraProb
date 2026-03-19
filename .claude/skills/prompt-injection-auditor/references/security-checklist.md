# NIST AI RMF Security Checklist (20+ Criteria)

Baseado no AI Risk Management Framework do NIST.

## 1. GOVERNANCE (GOV) - [5 Criteria]
- [ ] GOV-1.1: A skill tem um proprietário e propósito definido?
- [ ] GOV-1.2: Existe uma política de "Human-in-the-loop" para decisões de alto risco?
- [ ] GOV-1.3: As Invariantes de Negócio estão explicitamente mapeadas?
- [ ] GOV-1.4: O acesso a ferramentas externas é restrito ao mínimo necessário (Princípio do Menor Privilégio)?
- [ ] GOV-1.5: Existe um log de auditoria para cada execução de sistema?

## 2. MAPPING (MAP) - [5 Criteria]
- [ ] MAP-1.1: Todos os inputs de usuários são tratados como não confiáveis?
- [ ] MAP-1.2: A skill detecta inputs que tentam sair do contexto operacional?
- [ ] MAP-1.3: Existe mapeamento de dependências de bibliotecas de terceiros?
- [ ] MAP-1.4: O fluxo de dados entre "Trusted" e "Untrusted" está claro?
- [ ] MAP-1.5: A skill evita o uso de "System Commands" diretos via input?

## 3. MEASURING (MEASURE) - [5 Criteria]
- [ ] MEASURE-1.1: O `SECURITY SCORE` é recalculado em cada commit?
- [ ] MEASURE-1.2: É realizado teste de regressão com `adversarial-examples.md`?
- [ ] MEASURE-1.3: A latência do sistema é monitorada sob carga de segurança?
- [ ] MEASURE-1.4: A precisão da detecção de injection é avaliada (Falsos Negativos)?
- [ ] MEASURE-1.5: O sistema é testado contra payloads codificados (Base64/Hex)?

## 4. VeraProb DOMAIN COHERENCE (PF-DOM)
- [ ] PF-DOM-1.1: A skill respeita a INV-1 (Imutabilidade)? Nenhum comando de mutação detectado nas tabelas de fatos.
- [ ] PF-DOM-1.2: A skill usa o `EvaluationEngine` como autoridade única (INV-5)?
- [ ] PF-DOM-1.3: Existe sanitização explícita para dados vindos de `firecrawl` ou fontes externas?
- [ ] PF-DOM-1.4: O output da skill é determinístico (INV-7)?
- [ ] PF-DOM-1.5: A skill evita expor IDs de organizações diferentes no mesmo contexto (INV-6)?

## 5. MANAGING (MANAGE)
- [ ] MANAGE-1.1: Vulnerabilidades CRÍTICAS bloqueiam o uso da skill imediatamente?
- [ ] MANAGE-1.2: Existe um plano de resposta a incidentes para vazamento de prompt?
- [ ] MANAGE-1.3: O sistema de log expurga automaticamente segredos detectados?
- [ ] MANAGE-1.4: Fallbacks de segurança estão ativos se o modelo principal falhar?
- [ ] MANAGE-1.5: Atualizações periódicas dos padrões OWASP são aplicadas?
