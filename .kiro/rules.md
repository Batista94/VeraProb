# VeraProb - Global Rules & Invariants

Este arquivo define as regras inegociáveis e o contexto estático global para todos os agentes e operações no VeraProb.

## 1. PROTOCOLOS DE DESENVOLVIMENTO
- **TDD (Test-Driven Development)**: Falhar um teste (lançando `IntegrityException`) OBRIGATORIAMENTE antes de escrever o código de implementação.
- **DESIGN (Industrial Dark)**: 
  - Estética: Dark mode premium, glassmorphism, vibrações industriais.
  - UI: Espaçamento 8pt, fontes Inter/Outfit, micro-animações para feedback.
- **AUTONOMY**: Proatividade total. O "Council" de agentes deve agir sem esperar comandos triviais. O Lead Reviewer deve auditar todos os PRs.
- **SECURITY SCANNER**: Executar `bash scripts/security/pr_full_scanner.sh` antes de qualquer commit em branch protegida ou Merge para Main.

## 2. INVARIANTES FORENSES (INV-1 a INV-28)
As Invariantes são as leis fundamentais do VeraProb. Nenhuma alteração de código pode violá-las.
- **Fonte Única de Verdade (SSOT)**: Consulte sempre o arquivo [forensic_manifesto.md](file:///c:/Users/wes_b/Projects/VeraProb/docs/governance/forensic_manifesto.md).
- **Verificação Automática**: O gatilho `preCommit` aciona o `forensic-scanner`, que valida deterministicamente as regras INV-1 a 28 via regex e análise estática.
- **Principais Invariantes**:
  - **INV-1 (Identity Sovereignty)**: Todo fluxo deve validar `organization_id`.
  - **INV-6 (Universal UTC)**: Timestamps obrigatoriamente em UTC.
  - **INV-19 (Penny Precision)**: Valores financeiros como `BIGINT` (cents), nunca `double`.
  - **INV-26 (Error Parity)**: Erros idênticos (404) para evitar inferência de dados.
  - **INV-28 (Secret Guard)**: Bloqueio de segredos/tokens no código.

## 3. ORCHESTRATION (Makefile)
Utilize os comandos padronizados para gerenciar o ambiente:
- `make setup`: Constrói o ambiente, banco de dados e seeds.
- `make run`: Inicia o servidor de desenvolvimento local.
- `make check`: Executa o scanner de segurança e auditoria forense.
- `make help`: Lista todos os comandos disponíveis.

## 4. TECNOLOGIAS CORE
- **Frontend**: Flutter.
- **Backend/DB**: Supabase (PostgreSQL + RLS).
- **Architecture**: Agnostic core, C4 patterns, Wasm integration.
