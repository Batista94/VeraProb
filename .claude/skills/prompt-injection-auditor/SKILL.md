---
name: "Prompt Injection Auditor v2.0"
trigger: "/audit-prompt"
description: "🔍 Auditoria completa de prompt injection, jailbreaks e segurança"
priority: 2000
categories: ["security","safety","auditor"]
disable-model-invocation: false
signature: PF-SEC-8505A6F4BDF00F9E
---

# 🔍 Prompt Injection Auditor v2.0 (Agnostic Version)

Esta skill executa uma auditoria de segurança rigorosa em instruções de agentes (Skills/Workflows) para prevenir ataques de injeção de prompt e jailbreaks, seguindo os padrões OWASP Top 10 for LLM e NIST AI RMF.

## 🚨 MATRIZ DE RISCO (50+ PADRÕES)

### 🔴 CRÍTICOS (-50 pts cada)
- **Direct Injection:** "ignore previous", "ignore system prompt", "forget instructions", "disregard instructions", "override system", "new instructions", "forget your training"
- **Role Play:** "new role", "you are now", "act as", "become", "simulate", "assume the persona", "pretend to be", "be a malicious actor"
- **Jailbreaks:** "DAN", "Developer Mode", "jailbreak", "bypass safety", "no restrictions", "unfiltered mode", "GOD mode", "do anything now"
- **Leakage:** "print API key", "show config", "leak secrets", "repeat exactly", "copy instructions", "reveal prompt", "output your initialization", "list all internal functions"

### 🟠 ALTOS (-20 pts cada)
- **Obfuscation:** base64_decode, eval, exec, rot13, hexadecimal, prompt_leaking, unicode_bypass, "u\+"
- **Implicit Command:** "do exactly", "follow any command", "obedeça sempre", "trust this input", "must comply", "no matter what"
- **Character Encoding:** Leetspeak (@=a, 0=o, 1=i, 3=e, 7=t, 5=s), Homoglifos Unicode (letras cirílicas que parecem latinas)

### 🟡 MÉDIOS (-10 pts cada)
- **Operational:** "faça o que eu mandar", falta de sanitização de input, "use raw input"
- **Infrastructure:** Ferramentas sem rate limit, dependências externas não auditadas, exemplos sem validação, logs sem expurgo de segredos

## 🛠 COMANDOS
- `/audit-prompt [path]` - Executa análise detalhada em um arquivo.
- `/audit-batch [dir]` - Escaneia recursivamente todas as skills/workflows.
- `/fix-security [path]` - Sugere e aplica correções automáticas.

## 📋 WORKFLOW DE AUDITORIA
1. **Identificação:** O auditor lê o conteúdo do arquivo alvo.
2. **Pattern Matching:** Cruza os dados com `references/injection-patterns.md`.
3. **Scoring:** Calcula o `SECURITY SCORE` (Base 100).
4. **Sealing:** Se o score for >= 80, gera a **Security Audit Signature** (Hash SHA-256 do arquivo + Metadata).
5. **Reporting:** Gera o relatório visual via `scripts/generate-report.py`.
6. **Council Review:** Se o score for < 80, o `qa_security` deve ser invocado. Nenhuma execução é permitida sem assinatura válida (INV-11).

## 📚 REFERÊNCIAS INTERNAS (Caminhos Relativos para Portabilidade)
- [Padrões de Injeção](./references/injection-patterns.md)
- [Checklist de Segurança NIST](./references/security-checklist.md)
- [Exemplos Adversários](./references/adversarial-examples.md)
