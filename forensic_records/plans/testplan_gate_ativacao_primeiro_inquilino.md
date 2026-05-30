# Plano de Testes Consolidado: Gate de Ativação do Primeiro Inquilino (MVP de Entrada/Saída)

Este documento apresenta o plano de testes manuais para a homologação das entregas do Gate de Ativação do Primeiro Inquilino (MVP de Entrada/Saída) no projeto VeraProb.

---

## 📋 Visão Geral & Configuração de Ambiente

O objetivo deste plano é certificar os fluxos de entrada (Importador Universal de CSV) e de saída (Geração de Dossiê Forense PDF Executive-Grade) juntamente com as correções de acessibilidade (WCAG 2.1 AA), geocodificação legível e auditoria de modelos de SLA.

### 🔐 Credenciais de Acesso (Desenvolvimento)

* **Perfil:** Admin — Org Alpha (Inquilino Piloto)
* **E-mail:** `admin-a@veraprob.dev`
* **Senha:** `123456`
* **Org ID:** `00000000-0000-0000-0000-000000000001` (CNPJ: `11.222.333/0001-81`)

### 🚀 Inicialização do Ambiente

Certifique-se de que os containers do Supabase estão de pé e o banco de dados populado:

```bash
make setup
make run
```

---

## 🛡️ Regras de Negócio & Invariantes Mapeadas

Com base nas especificações forenses (`forensic-standards.md`) e nos requisitos da fase:

1. **Isolamento de Tenant (INV-1 & INV-22):** Toda importação de CSV e exportação de dossiê PDF deve ser restrita ao `organization_id` do usuário logado. As políticas de RLS e validações da aplicação utilizam obrigatoriamente a claim do JWT `(auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID` para garantir o isolamento físico. O Admin da Org Alpha **nunca** pode visualizar ou importar dados para a Org Beta.
2. **Representação Monetária (INV-4):** Os valores financeiros no Dossiê PDF (ex: economia acumulada) devem ser representados como `int` em centavos na aplicação e formatados com separador de milhar e decimal em reais (`R$ X.XXX,XX`) na UI.
3. **Cadeia de Custódia Imutável (INV-3):** Toda emissão de Dossiê PDF gera um hash SHA-256 (INV-9) e é registrada na tabela `pdf_dossier_logs` em modo append-only. Os privilégios de `UPDATE` e `DELETE` são explicitamente revogados para os perfis `authenticated` e `anon`.
4. **Idempotência de Dossiê (INV-15):** A tabela `pdf_dossier_logs` possui uma restrição UNIQUE para `(organization_id, sla_ledger_entry_id, document_hash_sha256)`, evitando duplicações ao re-emitir ou visualizar o mesmo veredito.
5. **Pre-flight de Entrada e Sanitização (CSV):** Qualquer erro de integridade de tipo (ex: capacidade numérica), formato estrutural de CNPJ/CPF (validação baseada no dígito verificador Mod-11), coordenada geográfica (Latitude/Longitude dentro dos limites físicos) ou injeção de fórmulas CSV/Stored XSS deve ser interceptado na pré-análise do CSV antes de persistir no banco.
6. **Estratégia de Importação Parcial (Partial Import):** Em caso de erros nas linhas do arquivo, o importador não bloqueia o lote inteiro (Emenda 2). Apenas as linhas com erros são ignoradas (com logs cirúrgicos exibidos na tela), enquanto as linhas limpas/válidas são importadas normalmente.
7. **Validação de Referência Estrangeira (FK Pre-flight):** No caso de contratos, se o CNPJ do contratante informado no CSV não estiver cadastrado sob a mesma organização ativa, a linha correspondente é marcada com erro `foreign_key_not_found` e pulada.
8. **Segurança de Ingestão de Binários (MIME Sniffing):** Enviar um arquivo binário disfarçado de CSV (ex: cabeçalho executável MZ `0x4D, 0x5A`) resulta em rejeição sumária e erro fatal de orquestração (`IntegrityException`), impedindo qualquer persistência (Emenda 1).
9. **Governança de SLA (Meta-Audit Log - INV-3):** Qualquer alteração nos modelos de SLA gera um registro imutável append-only na tabela `sla_template_audit_log` (com triggers de banco bloqueando UPDATE/DELETE com exceção `restrict_violation`).

### 📑 Matriz de Permissões e Imutabilidade (Controle UAT)

| Recurso / Fluxo | Papel | Autorizado? | Comportamento Esperado |
| :--- | :--- | :--- | :--- |
| **Upload de CSV** | Admin de Org | **SIM** | Acessa tela, mapeia colunas, valida pre-flight e salva dados válidos de sua org. |
| **Geração de PDF** | Admin de Org | **SIM** | Emite certificado PDF com dados do seu tenant e grava log imutável. |
| **Modificação de PDF Log** | Qualquer Papel | **NÃO** | Bloqueado pelo Postgres RLS e revogação de privilégios UPDATE/DELETE. |
| **Modificação de SLA Log** | Qualquer Papel | **NÃO** | Bloqueado por trigger restrict_violation e revogação de privilégios UPDATE/DELETE. |
| **Alteração de SLA** | Admin de Org | **SIM** | Qualquer alteração gera registro em `sla_template_audit_log`. |

---

## 🛠️ Cenários de Teste

### Grupo 1: Universal CSV Mapping Engine (Entrada)

#### CT01: Importação de CSV com Mapeamento Válido (Happy Path)
* **Objetivo:** Validar a importação completa de dados usando o mapeador universal com colunas válidas.
* **Pré-condições:** Logado como `admin-a@veraprob.dev`.
* **Passos:**
  1. Selecionar o pilar **"Administração"** no menu lateral e abrir a tela de gerenciamento de Ativos (Zonas/Operadores/Contratos).
  2. Clicar no botão **"Importar CSV"** no topo da tela para abrir o modal do Importador Universal.
  3. Selecionar o arquivo CSV de teste contendo registros válidos (ex: placa, capacidade, CNPJ, data de início).
  4. Na interface de mapeamento, correlacionar as colunas do CSV aos campos do sistema (ex: "PLACA" -> "identifier", "CAPACIDADE" -> "capacity").
  5. Clicar em **"Validar"** para rodar o Pre-flight.
  6. Com aprovação visual (0 erros e 100% das linhas válidas), clicar em **"Confirmar Importação"**.
* **Cenário Esperado:** A interface exibe a transição de passos: `UPLOAD` -> `MAPEAMENTO` -> `VALIDAÇÃO` -> `RESULTADO`, mostrando mensagem de sucesso e progresso de conclusão.
* **O que validar:**
  * Os registros aparecem nas respectivas listagens do sistema (agnóstico de entidade - INV-14).
  * O `organization_id` gravado no banco de dados é estritamente `00000000-0000-0000-0000-000000000001` (isolamento de tenant).
* **Requisito de Sucesso:** Mensagem visual de sucesso ("RESULTADO" concluído com 0 erros). Nenhum erro no console.

#### CT02: Pré-validação com Dados Inválidos e Importação Parcial
* **Objetivo:** Verificar a resiliência do parser a dados malformados, injeções perigosas, chaves inexistentes, arquivos executáveis e a execução do fluxo de Importação Parcial.
* **Passos:**
  1. Realizar o upload de um arquivo CSV configurado especificamente para disparar os seguintes erros de validação:
     * **Linha 1:** Deixar o campo de *Placa* vazio (sendo mapeado como `identifier` obrigatório).
     * **Linha 2:** Preencher o campo de *Capacidade* com `"X"` (texto ao invés de inteiro para `capacity`).
     * **Linha 3:** Preencher o campo de *Latitude* com `95.0` (fora do limite [-90, 90] para coordenadas).
     * **Linha 4:** Preencher o campo de *CNPJ* com `11.111.111/1111-11` (formato inválido/dígitos repetidos).
     * **Linha 5:** Duplicar o *CNPJ* usado na Linha 4 (duplicidade no mesmo lote).
     * **Linha 6:** Preencher o campo de *Data* com `"2026/05/29"` (quando o template de mapeamento está configurado para o formato brasileiro `dd/MM/yyyy`).
     * **Linha 7:** Preencher qualquer campo de texto com `=SUM(A1:A2)` ou `@import` (disparador de injeção de fórmulas CSV).
     * **Linha 8 (FK check):** Cadastrar um contrato mapeando `contractorDocument` com CNPJ `11.444.777/0001-61` que não esteja cadastrado na organização ativa.
     * **Linha 9 (Linha Limpa):** Inserir dados 100% corretos.
  2. Mapear as colunas correspondentes no passo de Mapeamento.
  3. Clicar em **"Validar"** para rodar o Pre-flight.
  4. Observar a tabela de erros gerada no passo de `VALIDAÇÃO`.
  5. Clicar no botão de confirmação para executar a **Importação Parcial** (apenas linhas válidas serão gravadas).
* **Cenário Esperado:** A UI deve exibir a tabela de erros detalhada (Step 3 - VALIDAÇÃO) apontando os erros de forma cirúrgica:
  * **Erro da Linha 1:** Código `required` | Mensagem: *"Valor obrigatório não preenchido."*
  * **Erro da Linha 2:** Código `invalid_number` | Mensagem: *"Capacidade deve ser um número inteiro válido."*
  * **Erro da Linha 3:** Código `invalid_coordinate` | Mensagem: *"Coordenada geolocalizada fora dos limites permitidos."*
  * **Erro da Linha 4:** Código `invalid_document` | Mensagem: *"Documento com dígito verificador inválido."*
  * **Erro da Linha 5:** Código `duplicate_in_batch` | Mensagem: *"Documento duplicado neste mesmo arquivo (visto na linha 4)."*
  * **Erro da Linha 6:** Código `invalid_date` | Mensagem: *"Data inválida para o formato esperado (dd/MM/yyyy)."*
  * **Erro da Linha 7:** Código `injection_detected` | Mensagem: *"Valor bloqueado por segurança (fórmula suspeita detectada)."*
  * **Erro da Linha 8:** Código `foreign_key_not_found` | Mensagem: *"Referência externa (FK) não encontrada no banco."*
* **Requisito de Sucesso:** A interface de validação exibe todos os erros listados com clareza. O sistema permite prosseguir e importar as linhas limpas (Linha 9), exibindo no passo `RESULTADO` que 1 linha foi importada e 8 linhas foram puladas.

#### CT02-B: Upload de Arquivo Executável (Pre-flight Blocker)
* **Objetivo:** Garantir a blindagem do orquestrador contra upload de payloads maliciosos disfarçados de CSV.
* **Passos:**
  1. Na tela de importação, selecionar um arquivo executável binário (com cabeçalho executável MZ `0x4D, 0x5A`) renomeado com a extensão `.csv`.
  2. Submeter o arquivo para validação.
* **Cenário Esperado:** O parser intercepta imediatamente a assinatura mágica do executável antes de qualquer processamento de colunas, exibindo uma mensagem de erro fatal na UI (`IntegrityException` indicando cabeçalho executável).
* **Requisito de Sucesso:** A transação é bloqueada em 100%, nenhuma linha é lida ou validada e nenhuma importação parcial é permitida.

#### CT03: Isolamento Cross-Tenant na Importação (Segurança)
* **Objetivo:** Garantir que dados de outros inquilinos não sejam modificados ou criados.
* **Passos:**
  1. Tentar forçar um payload contendo um `organization_id` de outro tenant (ex: Org Beta `...0002`) no corpo da requisição de importação.
* **Cenário Esperado:** A camada de segurança do Supabase/RLS ou a validação de domínio do Flutter rejeita a inserção baseado no JWT `auth.jwt() -> 'app_metadata' ->> 'org_id'`.

---

## Grupo 2: Executive-Grade Forensic PDF Certificate (Saída)

#### CT04: Geração de Certificado/Dossiê PDF (Sucesso)
* **Objetivo:** Validar a criação do dossiê forense PDF legível e assinado.
* **Pré-condições:** Viagem de teste finalizada/auditada na Fila Auditora.
* **Passos:**
  1. Acessar a Fila Auditora ou histórico de vereditos.
  2. Clicar no botão "Gerar Certificado Forense" ou "Selar Veredito".
  3. Aguardar o processamento da barra de progresso.
* **Cenário Esperado:** O navegador dispara o download de um arquivo PDF estruturado.
* **O que validar (Visual):**
  * O arquivo contém a cadeia de custódia e metadados forenses.
  * O valor monetário da economia está formatado em padrão brasileiro (`R$ X.XXX,XX`).
  * O layout está adaptado ao tema Industrial Dark (profissional, sem borrões ou quebras feias).
* **Requisito de Sucesso:** PDF aberto e inspecionado visualmente com sucesso.

#### CT05: Escrita no Ledger de Dossiê (Append-Only & Idempotência)
* **Objetivo:** Garantir a imutabilidade do histórico de geração de PDFs e a sua idempotência.
* **Passos:**
  1. Gerar o dossiê (CT04).
  2. Verificar no banco de dados se a tabela `pdf_dossier_logs` registrou o log de geração.
  3. Tentar executar uma query de UPDATE ou DELETE diretamente na tabela `pdf_dossier_logs` para aquela linha usando o papel `authenticated`.
  4. Gerar novamente o mesmo PDF com os mesmos dados da mesma viagem e verificar se o banco de dados evita registros duplicados (utilizando `ON CONFLICT DO NOTHING`).
* **Cenário Esperado:**
  * O banco de dados rejeita qualquer UPDATE ou DELETE com erro de permissão (403 / Permission Denied).
  * A re-geração do mesmo PDF é executada com sucesso de forma idempotente sem criar registros duplicados na tabela.
* **Requisito de Sucesso:** Nenhuma alteração/remoção de logs de PDF permitida no banco de dados.

---

## Grupo 3: Interface & Acessibilidade (UAT / Polish)

#### CT06: Validação de Contraste WCAG 2.1 AA
* **Objetivo:** Garantir legibilidade sob condições operacionais de 24/7.
* **Passos:**
  1. Navegar por todas as telas novas do fluxo (Importador CSV, abas de mapeamento e Visualizador de Veredito/PDF).
  2. Verificar se os contrastes de cores de textos secundários e badges estão nítidos e fáceis de ler no tema escuro.
* **Cenário Esperado:** Nenhuma combinação de texto/fundo deve apresentar dificuldade de leitura.

#### CT07: Geocodificação Reversa em Listas
* **Objetivo:** Garantir que o usuário veja endereços legíveis in vez de coordenadas de latitude/longitude brutas.
* **Passos:**
  1. Acessar a tela de vereditos ou histórico de telemetria.
  2. Inspecionar os campos de "Origem" e "Destino".
* **Cenário Esperado:** Exibição de nomes de ruas, cidades ou nomes de zonas personalizadas configuradas no contrato (ex: "Zona Industrial Alfa"), nunca `-23.55, -46.63`.

#### CT08: Auditoria de SLA (SLA Meta-Audit Log & Imutabilidade)
* **Objetivo:** Garantir que alterações nas regras de SLA fiquem registradas imutavelmente.
* **Passos:**
  1. Acessar a configuração de regras de SLA do tenant.
  2. Fazer uma alteração de tolerância (ex: tempo de atraso de 15 para 20 min).
  3. Salvar e conferir se um log foi gerado na tabela `sla_template_audit_log` com a identificação do autor, a data UTC exata e o valor anterior/novo.
  4. Tentar executar um UPDATE ou DELETE na tabela `sla_template_audit_log`.
* **Cenário Esperado:**
  * A alteração gera um registro `UPDATED` na tabela de auditoria.
  * O banco de dados bloqueia qualquer UPDATE ou DELETE na tabela `sla_template_audit_log` levantando um erro `restrict_violation` (código de erro `23001`).
* **Requisito de Sucesso:** Registros de alteração de SLA persistidos e protegidos contra alteração direta.
