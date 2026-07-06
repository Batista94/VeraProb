# Plano de Testes Consolidado: Gate de Ativação do Primeiro Inquilino (Fluxo de Entrada/Saída)

Este documento apresenta o plano de testes manuais para a homologação das entregas do Gate de Ativação do Primeiro Inquilino (Fluxo de Entrada/Saída) no projeto VeraProb.

---

## 📋 Visão Geral & Configuração de Ambiente

O objetivo deste plano é certificar os fluxos de entrada (Importador Universal de CSV) e de saída (Geração de Dossiê Forense PDF Executive-Grade) juntamente com as correções de acessibilidade (WCAG 2.1 AA), geocodificação legível e auditoria de modelos de SLA.

### 🔐 Credenciais de Acesso (Desenvolvimento)

* **Perfil:** Admin — Org Alpha (Inquilino Piloto)
* **E-mail:** `admin-a@veraprob.dev`
* **Senha:** `veraprob123!`
* **Org ID:** `00000000-0000-0000-0000-000000000001` (CNPJ: `78.423.287/0001-50`)

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
5. **Pre-flight de Entrada e Sanitização (CSV):** Qualquer erro de integridade de tipo (ex: capacidade numérica), documento (validação **contextual** por entidade — ver abaixo), coordenada geográfica (Latitude/Longitude dentro dos limites físicos), categoria de CNH ou injeção de fórmulas CSV/Stored XSS deve ser interceptado na pré-análise do CSV antes de persistir no banco.
   * **Validação contextual de documento (Mod-11):** O campo `contractorDocument` (Contratante) aceita **estritamente CNPJ** (14 dígitos) — CPF é rejeitado com mensagem focada em CNPJ (*"CNPJ inválido..."*). O campo `operatorDocument` (Operador/Motorista) aceita **estritamente CPF** (11 dígitos) — CNPJ é rejeitado com mensagem focada em CPF (*"CPF inválido..."*). Ambos validam o dígito verificador Mod-11.
   * **Categoria de CNH:** O campo `operatorLicenseCategory` aceita apenas categorias válidas (A, B, C, D, E ou combinações AB, AC, AD, AE, ACC), caso contrário levanta `invalid_license_category`.
   * **Validade de CNH:** O campo `operatorLicenseExpiry` é validado como data (ISO-8601 ou conforme o format hint), normalizada para UTC (INV-6).
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

## 🛠️ Cenários de Teste & Guia de Navegação UAT

### 🗺️ Guia de Navegação para Importação de CSV

Para testar a importação de CSV no ambiente, o usuário deve selecionar o pilar **"Administração"** no menu lateral. A partir do painel de Administração (Launcher), o usuário deve navegar especificamente para uma das três telas de cadastro para disparar o importador universal com a respectiva entidade:

1. **Zonas (Zonas Operacionais):**
   * **Onde clicar:** No painel de Administração, clique na opção **"Zonas Operacionais"**.
   * **Ação:** Clique no ícone de "Importar CSV" no cabeçalho da tela (canto superior direito).
   * **Entidade associada:** `zone`.
   * **Campos mapeáveis:** Nome da zona, latitude, longitude, raio (metros), endereço e ID externo. *(Observações e "código da zona" não são mais oferecidos — sem coluna no banco; use ID externo como código.)*
2. **Operadores (Motoristas):**
   * **Onde clicar:** No painel de Administração, clique na opção **"Motoristas"** (ou "Motoristas da Frota").
   * **Ação:** Clique no ícone de "Importar CSV" no cabeçalho da tela (canto superior direito).
   * **Entidade associada:** `operator`.
   * **Campos mapeáveis:** Nome do motorista, **CPF** (estrito, 11 dígitos), Número da CNH, Categoria da CNH, Validade da CNH, Telefone e ID externo. *(Observações não é oferecido — sem coluna no banco.)*
3. **Contratantes (Contractors):**
   * **Onde clicar:** No painel de Administração, clique na opção **"Contratantes"**.
   * **Ação:** Clique no ícone de "Importar CSV" no cabeçalho da tela (canto superior direito).
   * **Entidade associada:** `contractor`.
   * **Campos mapeáveis:** Nome do contratante, **CNPJ do contratante (obrigatório)**, e-mail do contratante, nome do contato e ID externo. *(Observações não é oferecido — sem coluna no banco.)*
   * **⚠️ MUDANÇA:** O CNPJ (`contractorDocument`) agora é **campo obrigatório** (chave de negócio + FK dos contratos). Se não for mapeado, o pre-flight levanta `unmapped_required`; valor em branco levanta `required`.
4. **Contratos (Contracts):**
   * **Onde clicar:** No painel de Administração, clique na opção **"Contratos"**.
   * **Ação:** Clique no ícone de "Importar CSV" no cabeçalho da tela (canto superior direito).
   * **Entidade associada:** `contract`.
   * **Campos mapeáveis:** Código do contrato, CNPJ do contratante, data de início, data de término, ID externo e observações.
   * **⚠️ PRÉ-REQUISITO UAT:** O CNPJ informado no CSV como contratante (`contractorDocument`) **deve já estar cadastrado** como contratante na base do tenant (cadastre um contratante manualmente na tela "Contratantes", ou via importação de CSV de Contratantes, com o CNPJ que será usado no CSV de contratos antes de rodar o teste de contratos, ou o pre-flight de contratos levantará `foreign_key_not_found`).

---

### Grupo 1: Universal CSV Mapping Engine (Entrada)

#### CT01: Importação de CSV com Mapeamento Válido (Happy Path — Premissa Fundamental)
* **Objetivo:** Validar a importação completa de dados usando o mapeador universal com colunas válidas em sua ordem de dependência lógica.
* **Pré-condições:** Logado como `admin-a@veraprob.dev`.

* **Fase 1: Importação de Contratantes (Massa Base)**
  1. Acessar a tela **"Contratantes"** em Administração.
  2. Clicar no botão **"Importar CSV"** no canto superior direito para abrir o modal.
  3. Fazer o upload do arquivo `test_csvs/contratantes_validos.csv`.
  4. Mapear as colunas (ex: `contractorName` -> Nome, `contractorDocument` -> Documento).
  5. Clicar em **"Validar"** (Pre-flight) e depois em **"Importar 3 linha(s)"**.
  * *Resultado:* Contratantes cadastrados com sucesso.

* **Fase 2: Importação de Contratos (Dependente)**
  1. Acessar a tela **"Contratos"** em Administração.
  2. Clicar em **"Importar CSV"** no canto superior direito.
  3. Fazer o upload do arquivo `test_csvs/contratos_validos.csv`.
  4. Mapear as colunas (ex: `contractCode` -> Código, `contractorDocument` -> Documento do Contratante).
  5. Clicar em **"Validar"** (Pre-flight) e depois em **"Importar 3 linha(s)"**.
  * *Resultado:* Contratos importados com sucesso, pois os CNPJs já existem na base (Fase 1).

* **O que validar no UAT:**
  * **Auto-Mapeamento (Fuzzy Matching):** Ao subir o CSV, colunas com nomes normalizados semelhantes (ex: "cnpj", "datainicio") devem vir automaticamente pré-selecionadas no menu de mapeamento de colunas.
  * **Isolamento de Dropdowns (Entity Isolation):** No dropdown de mapeamento, apenas os campos permitidos para a entidade ativa devem aparecer (ex: latitude e longitude não podem aparecer ao importar contratos).
  * **Visualização pós-importação:** Os registros devem aparecer na listagem do sistema correspondente ao fechar o modal.
  * **Tenant Lock:** O `organization_id` gravado no banco de dados deve ser obrigatoriamente o da Org Alpha (`00000000-0000-0000-0000-000000000001`).
* **Requisito de Sucesso:** Ambas as importações concluídas com sucesso ("RESULTADO" com 0 erros). Dados visíveis na listagem de Contratos e Contratantes.

#### CT02: Pré-validação com Dados Inválidos e Importação Parcial
* **Objetivo:** Verificar a resiliência do parser a dados malformados, injeções perigosas, chaves inexistentes e a execução correta da Importação Parcial (Partial Import).
* **Passos:**
  1. Fazer o upload do arquivo `test_csvs/contratos_invalidos.csv` contendo:
     * **Linha 1 (Vazio Obrigatório):** Código do contrato vazio (mapeado para `contractCode` obrigatório).
     * **Linha 2 (Valor Inválido):** Coordenada de latitude com valor `95.0` (fora de [-90, 90]) caso testado na tela de Zonas, ou Data inválida (ex: `"texto"`) para contratos.
     * **Linha 3 (CNPJ Inválido - Mod11):** CNPJ com formato numérico inválido ou dígitos repetidos (ex: `11.111.111/1111-11`).
     * **Linha 4 (Duplicidade no mesmo Lote):** Duplicar o mesmo CNPJ/Documento da Linha 3.
     * **Linha 5 (Data Malformada):** Data fora do padrão brasileiro esperado (ex: `"2026/05/29"` ao invés de `"29/05/2026"` configurado no format hint).
     * **Linha 6 (Tentativa de Injeção):** Um campo de texto começando com `=SUM(A1:A2)` ou `=1+1` (CSV Injection).
     * **Linha 7 (Chave Estrangeira Ausente - FK):** Inserir um CNPJ de contratante que não exista no banco de dados do seu tenant (ex: `11.999.999/9999-99`).
     * **Linha 8 (Linha Limpa/Válida):** Dados de contrato 100% corretos com CNPJ do contratante já existente na base.
  2. Mapear as colunas no modal.
  3. Clicar em **"Validar"** para rodar o Pre-flight.
  4. Observar a tabela de erros gerada no passo de `VALIDAÇÃO`.
  5. Clicar no botão de confirmação para executar a **Importação Parcial** (apenas linhas válidas serão gravadas).
* **Cenário Esperado & O que validar no UAT:**
  * O modal deve avançar para o passo **VALIDAÇÃO** exibindo uma tabela cirúrgica com os erros correspondentes:
    * **Linha 1:** Código `required` | *"Valor obrigatório não preenchido."*
    * **Linha 2:** Código `invalid_coordinate` ou `invalid_date` dependendo da tela.
    * **Linha 3:** Código `invalid_document` | *"CNPJ inválido. O documento do contratante deve ser um CNPJ com 14 dígitos e dígito verificador válido."* (mensagem contextual de CNPJ — este é um CSV de contratos, campo `contractorDocument`).
    * **Linha 4:** Código `duplicate_in_batch` | *"Documento duplicado neste mesmo arquivo."*
    * **Linha 5:** Código `invalid_date` | *"Data inválida para o formato esperado."*
    * **Linha 6:** Código `injection_detected` | *"Valor bloqueado por segurança (fórmula suspeita detectada)."*
    * **Linha 7:** Código `foreign_key_not_found` | *"Contratante não encontrado para o documento informado."*
  * **Importação Parcial:** O botão principal deve mostrar `"Importar 1 linha(s)"` (a linha limpa 8).
  * **Resultado Final:** Ao clicar em importar, o modal deve mostrar no passo **RESULTADO** que 1 linha foi importada com sucesso e 7 foram puladas, listando a tabela de erros correspondente às linhas ignoradas.
* **Requisito de Sucesso:** Sucesso na importação da linha limpa e bloqueio correto das linhas com erro de pre-flight ou FK.

#### CT02-B: Upload de Arquivo Executável (Pre-flight Blocker)
* **Objetivo:** Garantir a blindagem do orquestrador contra upload de payloads maliciosos disfarçados de CSV (MIME-Type Sniffing).
* **Passos:**
  1. Na tela de importação, selecionar um arquivo executável binário (com cabeçalho executável MZ `0x4D, 0x5A` ou um arquivo zip/pdf) renomeado com a extensão `.csv`.
  2. Submeter o arquivo para validação.
* **Cenário Esperado & O que validar no UAT:**
  * O parser deve interceptar imediatamente o upload no frontend/backend e exibir um erro fatal de integridade (`IntegrityException` indicando arquivo binário/cabeçalho executável bloqueado).
  * O fluxo deve ser inteiramente bloqueado, impedindo que o usuário avance para o passo de mapeamento.
* **Requisito de Sucesso:** Bloqueio imediato de arquivos binários não textuais com notificação clara de erro.

#### CT03: Isolamento Cross-Tenant na Importação (Segurança)
* **Objetivo:** Garantir que dados de outros inquilinos não sejam modificados ou criados.
* **Passos:**
  1. Subir o arquivo `test_csvs/contratos_cross_tenant.csv` contendo CNPJs ou IDs que pertencem a outra organização (ex: Org Beta).
* **Cenário Esperado & O que validar no UAT:**
  * O sistema executa o pre-flight sob o isolamento do JWT `auth.jwt()`. Qualquer CNPJ de outra organização é tratado como não existente no banco (gera erro `foreign_key_not_found` e o registro não é exposto).
  * Os dados inseridos no banco via upsert de CSV devem herdar automaticamente o `organization_id` do JWT ativo, impossibilitando gravação cruzada.

#### CT03-B: Importação de Operadores (CPF estrito + Compliance de CNH)
* **Objetivo:** Validar os campos consolidados de cadastro de motorista (CPF de identidade, número/categoria/validade de CNH) e a validação contextual de documento (CPF estrito).
* **Pré-condições:** Logado como `admin-a@veraprob.dev`. Importador aberto na tela **"Motoristas"** (`operator`).
* **Passos:**
  1. Subir o arquivo `test_csvs/operadores.csv` de motoristas com colunas: `nome`, `cpf`, `cnh` (número), `categoria`, `validade`, `telefone`.
  2. Mapear: `nome`→Nome do motorista, `cpf`→**CPF do Operador**, `cnh`→Número da CNH, `categoria`→Categoria da CNH, `validade`→Validade da CNH (format hint `dd/MM/yyyy`), `telefone`→Telefone.
  3. Incluir linhas adversas:
     * **Linha A (CNPJ no lugar de CPF):** Preencher `cpf` com um CNPJ válido (14 dígitos).
     * **Linha B (Categoria inválida):** Categoria `X` (fora de A/B/C/D/E/AB/AC/AD/AE/ACC).
     * **Linha C (Validade malformada):** `99/99/9999`.
     * **Linha D (Limpa):** CPF válido (11 dígitos), categoria `AD`, validade `31/12/2027`.
  4. Validar (Pre-flight).
* **Cenário Esperado & O que validar no UAT:**
  * **Linha A:** `invalid_document` | *"CPF inválido. O documento do operador deve ser um CPF com 11 dígitos..."* (mensagem focada em **CPF**, pois é a entidade Operador — CNPJ é rejeitado aqui).
  * **Linha B:** `invalid_license_category` | *"Categoria de CNH inválida..."*.
  * **Linha C:** `invalid_date` | *"Data inválida para o formato esperado (dd/MM/yyyy)."*.
  * **Linha D:** importada; categoria gravada em maiúsculas (`AD`), validade normalizada para UTC ISO-8601.
  * **Isolamento de dropdown:** apenas campos de `operator` aparecem (sem `contractorDocument`, sem latitude). "Observações" **não** é oferecido (sem coluna).
* **Requisito de Sucesso:** CPF validado estritamente; CNH categoria/validade validadas; linha limpa persistida com os novos campos.

---
---

## Grupo 2: Executive-Grade Forensic PDF Certificate (Saída)

#### CT04: Geração de Certificado/Dossiê PDF (Sucesso)
* **Objetivo:** Validar a criação do dossiê forense PDF legível e assinado.
* **Pré-condições:** Viagem de teste finalizada/auditada na Fila Auditora.
* **Passos:**
  1. Acessar a Fila Auditora ou histórico de vereditos.
  2. Clicar no botão "Gerar Certificado Forense" ou "Selar Veredito".
  3. Aguardar o download do arquivo PDF estruturado.
* **Cenário Esperado:** O navegador dispara o download de um arquivo PDF estruturado.
* **O que validar no UAT (Lista de Itens no PDF):**
  * **Estrutura por Páginas:**
    * **Página 1 — Atestado de Autenticidade (Capa):**
      * Deve possuir o cabeçalho `"ATESTADO DE AUTENTICIDADE — veraprob"`.
      * Deve exibir os IDs técnicos: `Report ID`, `Package ID`, `Package Hash` (SHA-256) e `Ledger Boundary` (Entry #).
      * Deve exibir o Emissor (Nome + CNPJ do seu tenant) e o Contratante (Nome + CNPJ).
      * O período do relatório deve vir no formato UTC e as datas no padrão ISO-8601 (AAAA-MM-DD).
      * A data de geração do PDF deve estar em UTC (`generatedAtUtc`).
      * Deve exibir o texto de legal notice e a instrução técnica de conferência de integridade.
    * **Página 2 — Resumo Executivo:**
      * Tabela contendo as métricas de faturamento e conformidade:
        * **Faturamento Total Contratado:** representado em reais (ex: `R$ 1.500,00`), convertido a partir do valor em centavos (`int` no banco).
        * **Receita Protegida (Blindada):** formatada com padrão monetário brasileiro.
        * **Receita em Risco** e **Receita Perdida (Penalidades):** formatadas em BRL.
        * **Taxa de Conformidade:** exibida como percentual (ex: `98.5%`).
        * Contadores absolutos de Obrigações, Executadas, No Shows e Gaps de evidência.
      * Tabela/Gráfico de distribuição de receita (% e BRL de cada categoria).
    * **Página 3 — Detalhamento Diário:**
      * Tabela mostrando cada dia da operação com colunas: Data, Total (R$), Protegido (R$), Em Risco (R$), Perdido (R$), Obrigações, Executadas, No Shows, Gaps, Conformidade (%) e Ledger ID.
    * **Página de Catálogo de Evidências (Se aplicável):**
      * Lista das evidências capturadas pelo Telegram Bot com colunas: Data/Hora (UTC), Tipo (Foto/Áudio), Hash SHA-256 (primeiros 16 caracteres + ...), Categoria, Motorista (ID truncado) e Vinculação (Vinculada/Órfã).
      * Notas de rodapé para evidências de áudio com indicação do hash completo no sistema.
      * Avisos de negligência para motoristas que consultaram o `/status` e foram avisados de pendências.
    * **Última Página — Cadeia de Custódia:**
      * O bloco de Cadeia de Custódia deve apresentar os 6 links/etapas de verificação manual de integridade:
        1. *Pacote de Exportação:* Fórmula de cálculo do Hash SHA-256.
        2. *Snapshots Diários:* IDs dos snapshots de auditoria diária.
        3. *Boundary do Ledger:* Número do Ledger Entry limite.
        4. *Traços de Avaliação:* Verificação via `evaluation_traces`.
        5. *Fatos Canônicos:* Rastreamento do payload original via `canonical_facts`.
        6. *Payload Bruto Selado:* Comparação com a hash salva em `raw_telemetry_payloads.payload_hash`.
  * **Visual & Legibilidade (Acessibilidade):**
    * Os textos secundários e metadados devem usar cores legíveis sob o padrão Industrial Dark (Zinc/Slate, sem cores vibrantes genéricas ou borrões).
    * Não deve haver quebras ou linhas órfãs entre as páginas.
* **Requisito de Sucesso:** PDF aberto e inspecionado visualmente cumprindo todos os pontos da lista acima.

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
* **Objetivo:** Garantir que o usuário veja endereços legíveis em vez de coordenadas de latitude/longitude brutas.
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
