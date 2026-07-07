---
name: ponytail-review
description: >
  Post-implementation skim for over-engineering. Run before declaring any task done.
---

# Ponytail Review

Quick pass on the diff — delete or inline anything that fails these checks:

1. **New abstraction with one caller?** Inline or delete.
2. **New helper for one use?** Inline unless security/RLS boundary.
3. **New file duplicating an existing pattern?** Extend the existing file.
4. **Config/factory for a single value?** Hardcode or use existing constant.
5. **Test that only asserts the obvious?** Delete (YAGNI on tests).

Output: bullet list of cuts made or "no cuts — diff already minimal."
