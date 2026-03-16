---
description: Manual validation plan for operational telemetry, SLA engine determinism, and data integrity.
---

# 🛡️ Plano de Blindagem Operacional

## Foco: Validação de Pipeline, Determinismo e Integridade de Dados

Este documento serve como guia para o "Bug Bash" de fundação. Não valide estética; valide a **Verdade dos Dados**.

---

### 🧱 ZONA 1: O CORAÇÃO DO LEDGER (Integridade)
**Objetivo:** Garantir que o sistema seja uma "Caixa Preta" inviolável.

- **[ ] Cenário 1.1: Escrita Forense**
    - **Ação:** No Command Center, selecione um veículo e registre uma ocorrência (ex: "Atraso por Manifestação").
    - **Validação UI:** O log deve surgir no `ForensicConsoleStrip` (rodapé).
    - **Validação DB:** Checar tabela `sla_audit_ledger` no Supabase. O payload JSON deve conter o texto exato e seu ID de operador.

- **[ ] Cenário 1.2: Tentativa de Fraude (Manual)**
    - **Ação:** No SQL Editor do Supabase, tente dar um `UPDATE` ou `DELETE` na tabela `sla_audit_ledger`.
    - **Resultado:** O banco DEVE retornar `permission denied` (RLS Hardening).

---

### ⚙️ ZONA 2: ENGINE DE SLA E DETERMINISMO
**Objetivo:** Validar se a "Inteligência operacional" toma as decisões certas.

- **[ ] Cenário 2.1: Binds de Geocerca**
    - **Ação:** Acionar o Fleet Simulator ou `DataSeeder`. Monitorar um veículo entrando no raio da parada.
    - **Validação:** O status na `execution_states` deve mudar de `pending` para `executed` sem intervenção humana.

- **[ ] Cenário 2.2: Reprocessamento Idempotente**
    - **Ação:** Disparar o fechamento financeiro do dia duas vezes seguidas.
    - **Resultado:** O saldo na tela de `Financial Impact` deve permanecer IDENTICO. Se duplicar o valor, a idempotência falhou.

---

### 🗺️ ZONA 3: REATIVIDADE DO OCC
**Objetivo:** Validar a resiliência da conexão em tempo real.

- **[ ] Cenário 3.1: Recuperação de Desconexão**
    - **Ação:** Abrir o Command Center e desligar o Wi-Fi. Esperar 30s. Ligar novamente.
    - **Resultado:** O sistema deve recompor os ícones no mapa e "pular" para a posição atual sem travar a UI.

- **[ ] Cenário 3.2: TTL de Telemetria**
    - **Ação:** Parar a injeção de dados de um veículo.
    - **Resultado:** Após 2 minutos de silêncio, o marcador deve desaparecer do mapa (Gestão de Memória).

---

### 👥 ZONA 4: GESTÃO DE RECURSOS (MANTENEDOR)
**Objetivo:** Validar o ciclo de vida dos ativos.

- **[ ] Cenário 4.1: Ciclo de Vida do Motorista**
    - **Ação:** Criar -> Editar (Mudar Status) -> Deletar (Confirmar Dialog).
    - **Validação:** Verificar se o `SkeletonLoader` aparece durante o sync e se a lista reflete o estado final sem refresh manual da página.

---

### 📋 CHECKLIST FINAL DE SESSÃO
- [ ] Houve alguma **Exception vermelha** no console do navegador?
- [ ] O valor em "Cents" no banco bate com o valor em "Reais" na tela?
- [ ] Todos os timestamps no banco estão em **UTC**? (Crucial para auditoria).
- [ ] Algum "Placeholder" (tela vazia) impediu a conclusão de um workflow?

---
*Gerado pelo Conselho de Engenharia*
