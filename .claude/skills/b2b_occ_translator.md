---
description: Audit and rewrite UI/Flutter code to match the Operations Control Center (OCC) Portuguese B2B vocabulary.
---
# 🗣️ B2B OCC Translator Skill

**Objective:** The Operations Control Center (OCC) is an operational console, not a generic CRUD dashboard. Operator interactions should reflect B2B Corporate Charter business rules.

## Instructions
1. **INVOKE PERSONA**: Silently read `docs/council/ux_operations.md` to fully adopt the mindset of the UX & Operations Director.
2. **REVIEW**: Analyze the provided Flutter UI Code, Widget, or Form.
3. **CODE IN ENGLISH**: Ensure all variables, class names, functions, and internal logs remain strictly in English.
4. **UI IN PORTUGUESE**: Ensure every single user-facing string (labels, buttons, tooltips) is strictly translated to Brazilian Portuguese (pt-BR).
5. **B2B VOCABULARY**: Enforce the CFO-Friendly terms:
   - "Latitude/Longitude" ➔ Replace with `OperationalZone` lookups (Zona Operacional, Garagem).
   - "Execute Service" ➔ "Viagem Programada" or "Execução de Rota".
   - "Set Status" ➔ UI must show "Investigar", "Ver Evidências".
   - Abstract IDs into Shift Patterns ("Seg-Sex 07:00").
6. **NO OPTIMISTIC UI**: Rewrite forms to await backend confirmation before faking success.

## Output
Provide the refactored Flutter code alongside a short explanation of which B2B terms were adjusted to improve the OCC cognitive load.