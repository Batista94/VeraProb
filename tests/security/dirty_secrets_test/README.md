# tests/security/dirty_secrets_test/README.md
# Forensic Scanner — Test Fixtures

Esses arquivos são **propositalmente sujos** para validar os 3 motores de detecção do `scan_secrets.py`.

| Arquivo | Motor | O que detecta |
|---|---|---|
| `dirty_level_a.dart` | Nível A (Regex) | Tokens Supabase (`sbp_`), GitHub PAT (`ghp_`), generic keys |
| `dirty_level_b.py` | Nível B (Entropia) | Strings aleatórias com entropia > 4.5 sem palavra-chave |
| `dirty_level_c.pem` | Nível C (Magic Bytes) | Cabeçalho de chave privada RSA |

## Como Testar Manualmente

```bash
# Stager um arquivo sujo e rodar o scanner
git add tests/security/dirty_secrets_test/dirty_level_a.dart
# Forçar o scanner a rodar ignorando a verificação de branch protegida:
FORCE_SCAN=1 python scripts/scan_secrets.py

# Esperado: EXIT 1 + linha mascarada impressa no terminal
```

> ⚠️ Esses arquivos estão na whitelist interna do scanner (`tests/security/dirty_secrets_test/`).
> Para testar, use a variável de ambiente `FORCE_SCAN=1` ou rode o script diretamente.
