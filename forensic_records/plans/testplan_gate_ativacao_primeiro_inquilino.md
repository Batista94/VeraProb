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

1. **Isolamento de Tenant (INV-1 & INV-22):** Toda importação de CSV e exportação de dossiê PDF deve ser restrita ao `organization_id` do usuário logado. O Admin da Org Alpha **nunca** pode visualizar ou importar dados para a Org Beta.
2. **Representação Monetária (INV-4):** Os valores financeiros no Dossiê PDF (ex: economia acumulada) devem ser representados como `int` em centavos na aplicação e formatados com separador de milhar e decimal em reais (`R$ X.XXX,XX`) na UI.
3. **Cadeia de Custódia Imutável (INV-3):** Toda emissão de Dossiê PDF gera um hash e é registrada na tabela `pdf_dossier_logs` em modo append-only (sem suporte a UPDATE ou DELETE).
4. **Valores de Pre-flight (CSV):** Qualquer erro de integridade de tipo, formato de CNPJ ou coordenada geográfica deve ser interceptado na pré-análise do CSV antes de persistir no Supabase.

### 📑 Matriz de Permissões e Imutabilidade (Controle UAT)

| Recurso / Fluxo | Papel | Autorizado? | Comportamento Esperado |
| :--- | :--- | :--- | :--- |
| **Upload de CSV** | Admin de Org | **SIM** | Acessa tela, mapeia colunas e salva dados da sua org. |
| **Geração de PDF** | Admin de Org | **SIM** | Emite certificado PDF com dados do seu tenant. |
| **Modificação de PDF Log** | Qualquer Papel | **NÃO** | Bloqueado pelo Postgres RLS (Append-only). |
| **Alteração de SLA Log** | Admin de Org | **SIM (Logado)** | Qualquer alteração de SLA gera registro em `sla_template_audit_log`. |

---

## 🛠️ Cenários de Teste

### Grupo 1: Universal CSV Mapping Engine (Entrada)

#### CT01: Importação de CSV com Mapeamento Válido (Happy Path)
* **Objetivo:** Validar a importação completa de dados usando o mapeador universal com colunas válidas.
* **Pré-condições:** Logado como `admin-a@veraprob.dev`.
* **Passos:**
  1. Navegar até o menu de Administração / Importador de Dados (CSV).
  2. Selecionar o arquivo CSV de teste contendo veículos ou contratos.
  3. Na interface de mapeamento, correlacionar as colunas do CSV aos campos do sistema (ex: "Placa" -> "vehicle_plate").
  4. Clicar em "Executar Pre-flight".
  5. Após aprovação visual sem erros, clicar em "Confirmar Importação".
* **Cenário Esperado:** O sistema exibe o progresso de importação e uma mensagem de sucesso ao final.
* **O que validar:**
  * Os registros aparecem nas respectivas listas (ex: Frota/Contratos).
  * O `organization_id` gravado no banco é estritamente `00000000-0000-0000-0000-000000000001`.
* **Requisito de Sucesso:** Mensagem visual de sucesso. Nenhum erro no console.

#### CT02: Pré-validação com Dados Inválidos (Pre-flight Validation)
* **Objetivo:** Verificar a resiliência do parser a dados malformados (CNPJ inválido, coordenadas de geofence erradas, etc.).
* **Passos:**
  1. Realizar o upload de um arquivo CSV configurado especificamente para disparar os seguintes erros de validação:
     * **Linha 1:** Deixar o campo de *Placa* vazio (sendo mapeado como obrigatório).
     * **Linha 2:** Preencher o campo de *Capacidade* com `"X"` (texto ao invés de inteiro).
     * **Linha 3:** Preencher o campo de *Latitude* com `95.0` (fora do limite [-90, 90]).
     * **Linha 4:** Preencher o campo de *CNPJ* com `11.111.111/1111-11` (formato inválido/dígitos repetidos).
     * **Linha 5:** Duplicar o *CNPJ* usado na Linha 4 (duplicidade no mesmo lote).
     * **Linha 6:** Preencher o campo de *Data* com `"2026/05/29"` (quando o template de mapeamento está configurado para o formato brasileiro `dd/MM/yyyy`).
     * **Linha 7:** Preencher qualquer campo de texto com `=SUM(A1:A2)` ou `@import` (disparador de injeção de fórmulas CSV).
  2. Mapear as colunas correspondentes no passo de Mapeamento.
  3. Clicar em **"Validar"** para rodar o Pre-flight.
* **Cenário Esperado:** A UI deve exibir a tabela de erros detalhada (Step 2 - VALIDAÇÃO) apontando os erros de forma cirúrgica:
  * **Erro da Linha 1:** Código `required` | Mensagem: *"Valor obrigatório não preenchido."*
  * **Erro da Linha 2:** Código `invalid_number` | Mensagem: *"Capacidade deve ser um número inteiro válido."*
  * **Erro da Linha 3:** Código `invalid_coordinate` | Mensagem: *"Coordenada geolocalizada fora dos limites permitidos."*
  * **Erro da Linha 4:** Código `invalid_document` | Mensagem: *"Documento com dígito verificador inválido."*
  * **Erro da Linha 5:** Código `duplicate_in_batch` | Mensagem: *"Documento duplicado neste mesmo arquivo (visto na linha 4)."*
  * **Erro da Linha 6:** Código `invalid_date` | Mensagem: *"Data inválida para o formato esperado (dd/MM/yyyy)."*
  * **Erro da Linha 7:** Código `injection_detected` | Mensagem: *"Valor bloqueado por segurança (fórmula suspeita detectada)."*
* **Requisito de Sucesso:** Todos os 7 erros específicos devem ser listados de forma legível na tabela de erros. O botão "Importar" deve exibir a contagem de linhas limpas e, se houver 0 linhas limpas, deve impedir a confirmação.

#### CT03: Isolamento Cross-Tenant na Importação (Segurança)
* **Objetivo:** Garantir que dados de outros inquilinos não sejam modificados ou criados.
* **Passos:**
  1. Tentar forçar um payload contendo um `organization_id` de outro tenant (ex: Org Beta `...0002`) no corpo da requisição de importação.
* **Cenário Esperado:** A camada de segurança do Supabase/RLS ou a validação de domínio do Flutter rejeita a inserção (ou força a gravação com o tenant do usuário autenticado).

---

### Grupo 2: Executive-Grade Forensic PDF Certificate (Saída)

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

#### CT05: Escrita no Ledger de Dossiê (Append-Only)
* **Objetivo:** Garantir a imutabilidade do histórico de geração de PDFs.
* **Passos:**
  1. Gerar o dossiê (CT04).
  2. Verificar no banco de dados se a tabela `pdf_dossier_logs` registrou o log de geração.
  3. Tentar executar uma query de UPDATE ou DELETE diretamente na tabela `pdf_dossier_logs` para aquela linha usando o papel `authenticated`.
* **Cenário Esperado:** O banco de dados rejeita a operação com erro de RLS.

---

### Grupo 3: Interface & Acessibilidade (UAT / Polish)

#### CT06: Validação de Contraste WCAG 2.1 AA
* **Objetivo:** Garantir legibilidade sob condições operacionais de 24/7.
* **Passos:**
  1. Navegar por todas as telas novas do fluxo 10.4.B (Importador CSV e Visualizador de Veredito/PDF).
  2. Verificar se os contrastes de cores de textos secundários e badges estão nítidos e fáceis de ler no tema escuro.
* **Cenário Esperado:** Nenhuma combinação de texto/fundo deve apresentar dificuldade de leitura.

#### CT07: Geocodificação Reversa em Listas
* **Objetivo:** Garantir que o usuário veja endereços legíveis em vez de coordenadas de latitude/longitude brutas.
* **Passos:**
  1. Acessar a tela de vereditos ou histórico de telemetria.
  2. Inspecionar os campos de "Origem" e "Destino".
* **Cenário Esperado:** Exibição de nomes de ruas, cidades ou nomes de zonas personalizadas configuradas no contrato (ex: "Zona Industrial Alfa"), nunca `-23.55, -46.63`.

#### CT08: Auditoria de SLA (SLA Meta-Audit Log)
* **Objetivo:** Garantir que alterações nas regras de SLA fiquem registradas imutavelmente.
* **Passos:**
  1. Acessar a configuração de regras de SLA do tenant.
  2. Fazer uma alteração de tolerância (ex: tempo de atraso de 15 para 20 min).
  3. Salvar e conferir na tabela `sla_template_audit_log`.
* **Cenário Esperado:** A alteração deve ser inserida na tabela de auditoria com a identificação do autor, a data UTC exata e o valor anterior/novo.
