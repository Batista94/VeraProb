---
description: Audit and rewrite UI/Flutter code to match the Operations Control Center (OCC) Portuguese B2B vocabulary.
---

# 🗣️ B2B OCC Translator Skill

**Objective:** The Operations Control Center (OCC) is an operational console, not a generic CRUD dashboard. Operator interactions should reflect B2B Corporate Charter business rules.

## Instructions
1. Review the provided Flutter UI Code, Widget, or Form.
2. Ensure **all** variables, class names, functions, and internal logs remain strictly in **English**.
3. Ensure **every single user-facing string** (labels, buttons, tooltips, dialogs, error messages) is strictly translated to **Brazilian Portuguese (pt-BR)**.
4. Enforce the CFO-Friendly, B2B Vocabulary:
   - "Latitude/Longitude" ➔ Replace with `OperationalZone` lookups (Zona Operacional, Garagem, Portaria).
   - "Execute Service" ➔ "Viagem Programada" or "Execução de Rota".
   - "Set Status" ➔ Only the engine does this. UI must show "Investigar", "Ver Evidências".
   - Abstract away generic database IDs into human-readable Shift Patterns ("Seg-Sex 07:00").
5. Look for Optimistic UI updates. If you see forms faking success before the Realtime backend confirms it, rewrite it to await backend confirmation.

## Output
Provide the refactored Flutter code alongside a short explanation of which B2B terms were adjusted to improve the OCC cognitive load.
