# 🧪 Plano de Teste Manual: Consolidação Phase 9.5 & 9.6

Este documento consolida os cenários de teste manual para as funcionalidades entregues na **Phase 9.5** e as planejadas/em desenvolvimento para a **Phase 9.6**. O foco é garantir a integridade dos dados, a precisão das lógicas matemáticas e a qualidade da nova experiência do cockpit.

---

## 🏗️ PARTE 1: Phase 9.5 — Vínculo Dinâmico & UX do Operador

**Objetivo:** Validar a flexibilidade operacional e a eficiência na configuração de contratos.

### [MT-9.5.1] SLA Template Library (Galeria de Modelos)

- **Ação:** Navegar até `Configurações > Templates de SLA`.
- **Passos:**
    1. Abrir a biblioteca de modelos.
    2. Selecionar o modelo "Fretamento" e o modelo "Carga Seca".
- **Expectativa:** Os campos de tolerância de tempo e regras de geocerca devem vir pré-preenchidos com valores padrão baseados no setor.

### [MT-9.5.2] Smart Defaults (Preenchimento Preditivo SQL)

- **Ação:** Criar um novo contrato para uma Organização (Tenant) existente.
- **Passos:**
    1. Iniciar o wizard de criação de Contrato.
    2. Identificar se campos como "Multa Base", "Velocidade Máxima" ou "Buffer de Geocerca" são sugeridos automaticamente.
- **Expectativa:** O sistema deve preencher os campos com base na média histórica daquele Tenant ou em heurísticas de sistema, reduzindo o esforço manual.

### [MT-9.5.3] ServiceManifest (Desacoplamento de Ativos)

- **Ação:** Gerenciar o vínculo entre Ativos e Obrigações.
- **Passos:**
    1. Vincular uma Placa a um `ServiceManifest`.
    2. Realizar uma alteração no Ativo (ex: mudar status para Manutenção).
    3. Verificar se o Contrato de SLA permanece estável e desacoplado.
- **Expectativa:** A exclusão ou alteração de um Ativo físico não deve corromper a estrutura lógica da obrigação contratual no ledger.

---

## 🧠 PARTE 2: Phase 9.6 — Lógicas Matemáticas & Cockpit UI

**Objetivo:** Validar a blindagem contra fraude e a reatividade da interface de monitoramento.

### [MT-9.6.1] Kinematic Guard (INV-17/25): Defesa contra Fake GPS

- **Ação:** Simular telemetria impossível via SQL Editor ou Fleet Simulator.
- **Passos:**
    1. Registrar um ponto de telemetria em `Cuiabá/MT`.
    2. Registrar um segundo ponto de telemetria 10 segundos depois em `São Paulo/SP` (Distância > 1000km).
- **Expectativa:** O sistema deve detectar a velocidade física impossível ($v = \Delta d / \Delta t$) e marcar o ponto como fraude, impedindo o disparo de um alerta falso de SLA.

### [MT-9.6.2] Visual Evidence Snapshots (Cards de Auditoria)

- **Ação:** Abrir a fila de auditoria (Auditor Queue).
- **Passos:**
    1. Selecionar um card de infração.
    2. Verificar a presença da miniatura do mapa (Snapshot).
- **Expectativa:** O snapshot deve mostrar: o ponto exato da infração, o contorno da Geofence em vermelho e o ponto anterior/posterior para contexto.

### [MT-9.6.3] Industrial Deep Theme (Cockpit UX)

- **Ação:** Trocar o tema da aplicação no Cockpit.
- **Passos:**
    1. Selecionar o tema "Industrial Deep".
- **Expectativa:** A interface deve assumir tons de `Slate/Zinc` (neutros). Verificar se não há fadiga visual excessiva (contraste balanceado) e se alertas vermelhos/amarelos possuem alta visibilidade contra o fundo escuro.

### [MT-9.6.4] Heurísticas de Alerta (Impacto em R$)

- **Ação:** Monitorar a lista de alertas ativos no Cockpit.
- **Passos:**
    1. Verificar o campo "Impacto Financeiro Estimado" em cada linha de alerta.
- **Expectativa:** O valor deve ser calculado em tempo real (ex: `Tempo de Atraso * Valor/Hora do Contrato`). O valor deve ser formatado corretamente em BRL (INV-19).

---

## 📝 Resumo de Validação Final

- [ ] Os dados financeiros seguem a regra de `BIGINT` (Money VO)?
- [ ] O cockpit mantém a performance com >50 veículos simultâneos?
- [ ] A cadeia de custódia (Hash Chain) foi mantida após o reprocessamento cinemático?

---

### VeraProb - Quality Assurance Protocol
