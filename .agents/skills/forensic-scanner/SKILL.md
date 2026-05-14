---
name: forensic-scanner
description: Executa a varredura determinística das Invariantes INV-1 a 28.
usage: /scan [file]
---

# Instructions

1.  **Execution**: Sempre que invocado, execute `node scripts/security/scanner_engine.js` passando a lista de arquivos alterados ou o arquivo específico fornecido no argumento.
2.  **Mapping**: Mapeie os resultados do JSON retornado para a interface de Diagnostics do Kiro.
3.  **Severity**:
    *   `BLOCK` -> Error (Bloqueia o commit).
    *   `WARN` -> Warning (Requer revisão manual do Lead Reviewer).
4.  **Verdict**: Se o JSON contiver `blocks > 0`, emita imediatamente o veredito `[NO-GO]`.
5.  **Proactive Guard**: Como `Lead Reviewer`, você deve garantir que:
    *   Toda migração que usa `SET NOT NULL` contenha o comentário `-- INV-DB: zero-downtime-verified`.
    *   Todo uso de `DateTime.now()` seja seguido por `.toUtc()`.
    *   Refira-se à seção `COMMON CI BLOCKS` no `CLAUDE.md` para padrões de correção.
