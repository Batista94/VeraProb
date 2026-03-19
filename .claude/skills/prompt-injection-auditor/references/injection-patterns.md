# OWASP Top 10 LLM - Enterprise-Grade Patterns (50+)

Este documento contém a base de conhecimento de padrões para detecção de ataques em LLMs.

## 1. Direct Prompt Injection (LLM01) - [20 Patterns]
| Category | Pattern / Regex | Weight |
|---|---|---|
| Instruction Override | `(?i)(ignore|disregard|forget|override|bypass)\s+(above|previous|original|system)\s+(prompt|instructions|rules)` | CRITICAL |
| Developer Modes | `(?i)(Developer\s+Mode|DAN|AIM|DUDE|STAN|JAILBREAK|NEVER\s+SAY\s+NO)` | CRITICAL |
| Role Manipulation | `(?i)(act\s+as|you\s+are\s+now|assume\s+the\s+role|become|simulate|pretend|identity\s+shift)` | CRITICAL |
| Secret Extraction | `(?i)(print|show|reveal|display|output|leak|dump)\s+(config|secrets|api_key|system_prompt|hidden|internal)` | CRITICAL |
| Confirmation Attack | `(?i)(confirm|acknowledge|say\s+yes)\s+to\s+the\s+following\s+malicious\s+command` | HIGH |

## 2. Insecure Output Handling (LLM02) - [10 Patterns]
| Category | Pattern / Regex | Weight |
|---|---|---|
| XSS Payloads | `(?i)(<script|javascript:|onerror=|onload=)` | HIGH |
| Markdown Injection| `(?i)(\!\[.*\]\(javascript:.*\)|\[.*\]\(javascript:.*\))` | HIGH |
| SQLi in Prompt | `(?i)(SELECT\s+.*\s+FROM|DROP\s+TABLE|UNION\s+SELECT|--|;\s*DELETE)` | HIGH |

## 3. Data Leakage & Privacy (LLM06) - [10 Patterns]
| Category | Pattern / Regex | Weight |
|---|---|---|
| PII Discovery | `(?i)(email|password|credit\s+card|social\s+security|SSN|address|phone|birthdate)` | MEDIUM |
| Internal Directory | `(?i)(C:\\Windows|/etc/passwd|/var/log|index\.php|web\.config|\.env)` | HIGH |

## 4. Adversarial Encoding (LLM04) - [10 Patterns]
| Category | Pattern / Regex | Weight |
|---|---|---|
| Base64 Leak | `(?:[A-Za-z0-9+/]{40,})` (Long strings potentially being base64 data) | HIGH |
| Hex/Unicode Escape| `(\\x[0-9a-fA-F]{2}|\\u[0-9a-fA-F]{4})` | HIGH |
| Leetspeak Filter | `(?i)([a@][s$][s$]|f[u\*][ck]|b[i!]tch|p0rn|h4ck)` | MEDIUM |
| Character Substitute| `(?i)(h[4a]ck|s[3e]cr[3e]t|p[4a]ssw[0o]rd|4p[i!] key)` | MEDIUM |

## 5. Business Invariant Breach (PF-INV)
| Category | Pattern / Regex | Weight |
|---|---|---|
| Ledger Mutation | `(?i)(DELETE\s+FROM|UPDATE\s+.*SET|apagar|deletar|alterar)\s+(ledger|events|fatos|transactions)` | CRITICAL |
| Human Override | `(?i)(manual\s+override|forçar\s+estado|comando\s+humano|force\s+state|override\s+ledger)` | CRITICAL |
| Indirect Jailbreak | `(?i)(ignore\s+instructions\s+in\s+the\s+following\s+document|instructions\s+from\s+URL|external\s+rules)` | CRITICAL |
| Tenant Boundary | `(?i)(bypass\s+RLS|access\s+other\s+tenant|cross-tenant|all\s+organizations)` | CRITICAL |

*Total patterns monitored: 60+*
