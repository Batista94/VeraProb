# UAT Plan — Phase 10.4.C: Evidence Audit Modal

**Feature:** Exibição do snapshot forense read-only + verificação de integridade de hash na Fila Auditora.
**Branch:** `feature/evidency-proof`
**Gerado em:** 2026-06-02

---

## Pré-requisitos

| Item | Ação |
|------|------|
| App rodando | `make run` |
| Supabase local up | `make setup` (se não estiver) |
| Conta de admin | Login com credencial admin válida (admin tem permissão igual ou superior ao auditor) |
| Veredito selado existente | Se não houver, execute o **Setup TC-00** antes dos outros TCs |

---

## Setup TC-00 — Criar e Selar um Veredito (pré-condição)

> Execute uma única vez antes de TC-01 a TC-07.

**Passos:**

1. Faça login com credencial de admin.
2. Navegue: menu lateral → **Fila Auditora** (a tela exibe "Tribunal de Auditoria" internamente).
3. Verifique se a aba **"Pendentes"** está ativa.
4. Clique em **"Gerar Sanção de Teste"** (botão outlined no canto superior direito).
   - Aguarde o SnackBar: *"Sanção VEL-01 injetada — aguarde até 5s para aparecer na fila."*
5. Após o card aparecer na lista (até 5s), clique nele para expandir.
6. Clique em **"SELAR VEREDITO"** (botão verde).
7. Se aparecer diálogo de confirmação de integridade baixa ("⚠ Integridade Baixa"), clique **"Confirmar Selamento"**.
8. O card deve desaparecer da fila de pendentes.

**Checkpoint:** Mude para a aba **"Selados"** — o veredito recém-selado deve aparecer com badge `🔒 SELADO`.

> **ATENÇÃO:** Para o TC-00 funcionar, é necessário ter ao menos um contrato ativo no banco.
> Se "Gerar Sanção de Teste" falhar com "Verifique se há contratos ativos", o problema é que nenhum
> contrato foi importado/salvo. Verifique o fluxo de importação de Contratantes → Contratos antes.

---

## TC-01 — Happy Path: Modal de Evidência Autêntica

**Objetivo:** Verificar que clicar "Visualizar Evidência Forense" abre o modal com dados corretos e banner de autenticidade.

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | Navegue → **Fila Auditora** → aba **"Selados"** | Lista de vereditos selados visível |
| 2 | Localize card com badge `🔒 SELADO` | Card com opacidade reduzida (~60%) visível |
| 3 | Clique em **"Visualizar Evidência Forense"** (botão outlined azul com ícone de escudo) | Modal abre, título **"Cópia Forense da Regra"** visível |
| 4 | Observe o banner no topo do conteúdo | Banner **verde** com ícone `verified_user` + texto **"Cópia Autenticada"** |
| 5 | Verifique seção **"INFORMAÇÕES DE REGISTRO"** | Campos: Vigência Início, Vigência Fim, Selado Por (Operador), Selado Em. Cada campo com ícone de cadeado à esquerda do valor |
| 6 | Verifique seção **"PARÂMETROS CONGELADOS"** | Um ou mais blocos com "Regra: [ID]", badge de versão `v1`, parâmetro legível (ex: "Tolerância Máxima de Atraso: X minutos") |
| 7 | Verifique seção **"VERIFICAÇÃO CRIPTOGRÁFICA"** | Label "Hash Selado (SHA-256):" + string hexadecimal longa (64 chars) |
| 8 | O hash deve ser **selecionável** | Clique e arraste sobre o hash — deve selecionar o texto |

---

## TC-02 — Read-Only: Nenhum campo editável no modal

**Objetivo:** Confirmar imutabilidade visual — zero inputs, zero botões de edição.

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | Com o modal aberto (TC-01 passo 3) | — |
| 2 | Inspecione todos os valores exibidos | **Nenhum** TextField, DropdownButton, Checkbox, Switch visível |
| 3 | Procure botões | Apenas: `✕` (fechar) no header. **Nenhum** "Salvar", "Editar", "Atualizar" |
| 4 | Tente dar duplo-clique em qualquer label de valor | Nenhuma ação ocorre — campo não ativa modo de edição |

---

## TC-03 — Timezone: Datas exibidas em horário local

**Objetivo:** Garantir que timestamps UTC são traduzidos para fuso do operador com sufixo de timezone.

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | No modal aberto, observe campo **"Selado Em (Data)"** | Formato `DD/MM/YYYY HH:MM:SS (BRT)` — ou timezone local do sistema |
| 2 | Observe **"Vigência Início"** e **"Vigência Fim"** | Mesmo formato. Se sem vigência definida, exibe `N/A` |
| 3 | Confirme que nenhuma data exibe sufixo `UTC` ou `Z` | Datas convertidas para local com nome do timezone |

---

## TC-04 — Estado de Loading

**Objetivo:** Verificar feedback visual enquanto evidência carrega do backend.

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | Abra modal em veredito recém-criado | — |
| 2 | Clique "Visualizar Evidência Forense" imediatamente após selar | Modal abre com `CircularProgressIndicator` centralizado |
| 3 | Aguarde carregamento completar | Indicador desaparece, conteúdo renderiza |

---

## TC-05 — Fechamento do Modal

**Objetivo:** Modal fecha corretamente sem afetar a fila.

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | Com modal aberto | — |
| 2 | Clique no ícone `✕` no header | Modal fecha |
| 3 | Verifique fila de selados | Cards permanecem intactos, filtro de data não resetou |
| 4 | Reabra o modal do mesmo card | Modal abre novamente com mesmos dados |
| 5 | Pressione `Esc` no teclado | Modal fecha (comportamento padrão Dialog) |

---

## TC-06 — Estado de Erro: Evidência não encontrada

**Objetivo:** Verificar que erro do backend exibe mensagem amigável (não stack trace).

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | (Requer acesso ao banco) Pause Supabase: `supabase stop` | — |
| 2 | Tente abrir modal de qualquer card selado | Modal exibe: `"Erro ao carregar evidência: [mensagem de erro]"` em vermelho |
| 3 | A mensagem **não** deve conter stack trace, `[DBG]`, ou mensagem de infra | Apenas mensagem de domínio |
| 4 | Feche o modal | Modal fecha normalmente |

---

## TC-07 — Cadeia de Custódia (Forensic Seal Row)

**Objetivo:** Verificar que a Zona 4 do card (Cadeia de Custódia) abre o modal de investigação, distinto do modal de evidência.

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | No card selado, localize a seção cinza com ícone azul + **"Cadeia de Custódia · Prova Forense"** + hash SHA-256 truncado | Seção visível logo acima do botão "Visualizar Evidência Forense" |
| 2 | Clique na seção (area inteira é clicável) | **InvestigationModal** abre (modal diferente — exibe telemetria/mapa) |
| 3 | Feche esse modal | Retorna à fila |
| 4 | Confirme que os dois botões são distintos | "Cadeia de Custódia" → InvestigationModal; "Visualizar Evidência Forense" → ForensicEvidenceModal |

---

## TC-08 — Detecção de Adulteração (Tamper Detection)

> **Requer acesso direto ao banco com service_role.**

**Objetivo:** Verificar que hash divergente ativa view de alerta crítico e bloqueia exibição dos parâmetros.

**Preparação:**
```sql
UPDATE forensic_evidence_vault
SET integrity_hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
WHERE ledger_entry_id = '<id-do-veredito-selado>';
```

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | Após executar SQL acima, abra o modal do veredito adulterado | — |
| 2 | Observe o banner | Banner **VERMELHO** com ícone `gavel_rounded` + título **"Divergência Crítica de Integridade"** |
| 3 | Leia o subtítulo | "Suspeita de Fraude no Banco de Dados. Os parâmetros desta regra foram adulterados após o selamento do veredito." |
| 4 | Parâmetros **não são exibidos** | Seção com cadeado + "A leitura dos parâmetros desta cópia foi bloqueada de forma preventiva..." |
| 5 | Botão **"ESCALAR INCIDENTE"** visível (vermelho) | Visível e habilitado |

---

## TC-09 — Escalação de Incidente de Segurança

> Depende de TC-08 — execute em sequência.

**Objetivo:** Verificar que escalação envia log de segurança e exibe feedback.

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | Com view de adulteração aberta (TC-08) | — |
| 2 | Clique **"ESCALAR INCIDENTE"** | Botão entra em loading: ícone substituído por spinner branco |
| 3 | Aguarde resposta | SnackBar verde: **"Incidente de segurança escalado com sucesso."** |
| 4 | Verifique no banco | Registro com `event_type = 'SECURITY_INCIDENT_ESCALATION_REQUESTED'` e `ledger_entry_id` correto |

---

## TC-10 — Layout Responsivo

**Objetivo:** Modal não transborda em telas menores.

| # | Passo | Resultado Esperado |
|---|-------|--------------------|
| 1 | Redimensione janela do browser para ~768px de altura | — |
| 2 | Abra modal de evidência | Modal ocupa no máximo **85% da altura** da tela |
| 3 | Conteúdo é rolável | Scroll interno no modal funciona |
| 4 | Header ("Cópia Forense da Regra" + `✕`) permanece fixo | Header não rola junto com conteúdo |

---

## Resumo de Critérios de Aceite

| TC | Critério de Aceite | Blocker? |
|----|-------------------|----------|
| TC-00 | Veredito selado aparece na aba "Selados" | Sim (pré-req) |
| TC-01 | Modal abre com banner verde "Cópia Autenticada" e 3 seções | **Sim** |
| TC-02 | Zero campos editáveis ou botões de edição | **Sim** |
| TC-03 | Datas exibem timezone local (não UTC) | Sim |
| TC-04 | Loading spinner visível enquanto carrega | Não |
| TC-05 | `✕` e `Esc` fecham modal; fila intacta | Sim |
| TC-06 | Erro exibe mensagem de domínio, não stack trace | Sim |
| TC-07 | "Cadeia de Custódia" e "Visualizar Evidência" abrem modais distintos | Sim |
| TC-08 | Hash adulterado mostra view de alerta crítico, bloqueia parâmetros | **Sim** |
| TC-09 | Escalação registra evento no banco e exibe SnackBar verde | Sim |
| TC-10 | Modal scrollável, não transborda, header fixo | Não |

---

## Notas

- TC-08/09 requerem acesso ao banco com `service_role` para simular adulteração.
- TC-06 requer parar o Supabase local ou bloquear requests via DevTools.
- TC-00 depende de contratos ativos no banco — resolver importação de Contratantes → Contratos antes.
- Perfil de admin tem `hasPermission(auditor) == true` — todas as ações do Tribunal de Auditoria estão acessíveis.
