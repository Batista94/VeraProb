# Plano de Testes E2E UAT — SLA Sandbox Simulator (Fase 10.8)

Este documento descreve as etapas de teste manuais (User Acceptance Testing) para validar o motor de simulação de SLA (Sandbox) e garantir o funcionamento de ponta a ponta, desde a interface até as restrições de banco de dados.

---

## 1. Pré-Requisitos e Setup
- **Usuários:** 
  - Usuário A (`admin-a@veraprob.dev`): Administrador do Tenant (com permissão implícita de `sandbox:simulate`).
  - Usuário B (`operador@veraprob.dev`): Operador sem a permissão `sandbox:simulate`.
  *(Ambos são criados automaticamente pelo script `bootstrap_dev.mjs` ao rodar `make setup`)*
- **Massa de Dados:** 
  - A massa de dados de teste (Fornecedores, Rotas, Motoristas, Contratos e Penalidades Históricas no Ledger) pode ser gerada automaticamente no ambiente de testes clicando no botão **"SIMULAR OPERAÇÃO"** (ícone de raio) no canto superior direito do Dashboard Principal.
  - *Nota:* Este botão só é exibido para perfis com permissões administrativas ou de validador.
- **Caminho de Navegação na UI:**
  - Fazer login -> Dashboard Administrativo (`/admin/hub`) -> Clicar em "SIMULAR OPERAÇÃO" (para gerar dados, caso a base esteja limpa) -> Acessar a listagem de Contratos -> Selecionar o contrato desejado -> No topo direito da tela de detalhes do contrato (ao lado do botão "Regras SLA" e dos badges de status), localizar o botão **"Simular ROI"** (ícone de frasco científico `Icons.science_outlined`).

---

## 2. Validação de Permissões (RBAC)

| Passo | Ação | Resultado Esperado |
| :--- | :--- | :--- |
| **2.1** | Fazer login com o **Usuário B** (`operador@veraprob.dev` - Sem permissão). | Login efetuado com sucesso. |
| **2.2** | Tentar acessar o Sandbox clicando no botão **"Simular ROI"** no painel de detalhes do contrato, ou acessando diretamente `/admin/hub/contracts/CONTRACT_ID/sandbox`. | O botão **"Simular ROI"** (key: `contract-simulate-roi-button`) deve estar **oculto** para este perfil. Se tentar acessar a URL diretamente no navegador, o sistema deve redirecionar silenciosamente de volta para o Dashboard Administrativo (`/admin/hub`), garantindo o princípio Anti-Oracle (INV-26). |
| **2.3** | Fazer logout e login com o **Usuário A** (`admin-a@veraprob.dev` - Tenant Admin). | O botão **"Simular ROI"** deve estar visível no cabeçalho do contrato. Ao clicar nele, o acesso é liberado e o usuário é direcionado para a tela de Simulação (`/admin/hub/contracts/CONTRACT_ID/sandbox`). |

---

## 3. Validação de Regras de Negócio e Inputs

Com o **Usuário A** (`admin-a@veraprob.dev`) logado na tela de Simulação do Contrato:

| Passo | Ação | Resultado Esperado |
| :--- | :--- | :--- |
| **3.1** | Definir um período de simulação **maior que 6 meses** (ex: 01/01/2026 a 01/10/2026) nos seletores de data e tentar simular. | O sistema deve exibir o erro de validação **"O período máximo permitido é de 6 meses"** em texto vermelho abaixo dos inputs e manter o botão **"Executar Simulação"** desabilitado. |
| **3.2** | Definir uma Data Final que seja **anterior** ou **igual** à Data Inicial (ex: Data Inicial: 15/02/2026, Data Final: 10/02/2026). | O sistema deve exibir o erro de validação **"A data final deve ser posterior à data inicial"** e manter o botão **"Executar Simulação"** desabilitado. |
| **3.3** | Tentar inserir valores que não sejam numéricos ou negativos nos campos de overrides financeiros ("Teto mensal de multas" e "Multa base"). | O campo (do tipo `BRL Currency Input Formatter`) deve bloquear a digitação de quaisquer caracteres que não sejam dígitos, impossibilitando valores negativos ou formatos inválidos. |

---

## 4. Simulação: Caminho Feliz (What-If Analysis)

Com o **Usuário A** (`admin-a@veraprob.dev`), selecione um período válido (ex: últimos 3 meses) que contenha infrações históricas.

| Passo | Ação | Resultado Esperado |
| :--- | :--- | :--- |
| **4.1** | No formulário de simulação, preencher os overrides: <br>- **Nome da sessão:** "Simulação de Teste UAT" <br>- **Tolerância de atraso:** Ajustar o slider para 20 min <br>- **Teto mensal de multas (opcional):** R$ 5.000,00 <br>- **Multa base (opcional):** R$ 150,00 | O botão **"Executar Simulação"** deve se tornar habilitado assim que todas as validações passarem. |
| **4.2** | Clicar no botão **"Executar Simulação"**. | A UI deve exibir um estado de *Loading* no botão. A chamada RPC `simulate_sla_sandbox()` é disparada em background. |
| **4.3** | Aguardar a conclusão da simulação. | O formulário deve dar lugar à tela de **Resultados da Sessão** com os dados comparativos (Baseline vs Simulado) estruturados. |

---

## 5. Validação dos Resultados da Simulação (Auditabilidade)

Na tela de Resultados da Simulação gerada no passo anterior:

| Passo | Ação | Resultado Esperado |
| :--- | :--- | :--- |
| **5.1** | Verificar o valor do **Baseline** gerado. | O valor no card "BASELINE (Regras Atuais)" deve corresponder EXATAMENTE ao total das penalidades reais aplicadas naquele período (Ledger de produção). |
| **5.2** | Verificar a formatação monetária (Cognitive-shield). | Valores simulados no card **"SIMULADO (Regras Hipotéticas)"** devem utilizar a cor cinza/prata (`VeraProbColors.textSecondary`) e conter o prefixo `~` (ex: `~R$ 4.500,00`). O card de **"ECONOMIA PROJETADA"** (ou "AUMENTO PROJETADO") deve utilizar a respectiva cor semântica (Verde para Economia, Laranja/Amber para Aumento) e conter o prefixo `~`. |
| **5.3** | Validar o **Teto Mensal (Cap)** simulado. | Se as multas simuladas no período passaram de R$ 5.000,00 (conforme override), o valor final total simulado deve estar limitado a R$ 5.000,00. No banco de dados (`sandbox_simulation_results`), os eventos afetados após o estouro do limite devem conter `simulated_cap_truncated = true`. |
| **5.4** | Validar o **Delta** (Economia/Prejuízo). | O cálculo do Delta e do Delta BPS (Pontos Base) deve refletir corretamente a diferença matemática entre a Baseline e a Simulação. |
| **5.5** | Tentar sair do modo simulação e conferir a imutabilidade. | A UI não deve apresentar controles para editar ou excluir a simulação. A simulação pode ser abandonada clicando no botão **"Sair Simulação"** (no banner superior de aviso) ou **"Sair do Modo Simulação"** (no rodapé dos resultados), retornando ao painel do contrato. |

---

## 6. Segurança e Isolamento de Tenants (Cross-Tenant)

*Este teste pode exigir interceptação de API (Postman/Curl) se a UI não permitir manipulação direta do Contract ID.*

| Passo | Ação | Resultado Esperado |
| :--- | :--- | :--- |
| **6.1** | Com o Token do Usuário A (`admin-a@veraprob.dev` - Tenant A), disparar uma requisição para a RPC `simulate_sla_sandbox` enviando o `contract_id` pertencente ao **Tenant B**. | A transação deve falhar silenciosamente com erro de não encontrado (Anti-Oracle / INV-26). Nenhuma simulação deve ser gerada, garantindo o RLS (Row Level Security). |

---

## 7. Validação do Garbage Collector (Rotina de Limpeza)

Este teste valida a infraestrutura em background que limpa sessões antigas, economizando espaço (GDPR/Data Lifecycle).

| Passo | Ação | Resultado Esperado |
| :--- | :--- | :--- |
| **7.1** | Inserir/Criar simulações que possuam uma data de expiração (TTL) no passado (pode exigir acesso direto ao DB para setar o `expires_at` para ontem). | Sessão pronta para ser deletada. |
| **7.2** | Executar manualmente a RPC de limpeza via SuperAdmin ou DB: `SELECT gc_sandbox_simulations();` | O retorno deve indicar a quantidade de linhas removidas. |
| **7.3** | Verificar os resultados na UI ou DB. | As sessões expiradas sumiram, porém o log de auditoria `system_audit_log` registrou o evento `SANDBOX_GC_EXECUTED` provando a conformidade legal. |
