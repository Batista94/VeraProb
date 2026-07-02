# UX Standards - VeraProb

## Design System: Indigo Zinc (Industrial Dark)

The VeraProb interface follows a premium, high-density industrial aesthetic —
Linear/Vercel-like. Dark-only product.

### 1. Color Palette (Indigo Zinc)

| Token | Hex | Usage |
|-------|-----|-------|
| `background` | `#09090B` | Scaffold/page background |
| `surface` | `#101013` | Cards, panels |
| `surfaceElevated` | `#18181D` | Elevated surfaces, popovers |
| `border` | `rgba(255,255,255,0.10)` | All borders (white @ 10%) |
| `primary` | `#6E7CF6` | CTA buttons, active states, links |
| `accent` | `#93A0FF` | Hover states, gradient end |
| `secondary` | `#5EEAD4` | Teal — support/highlight only |
| `textPrimary` | `#E4E4E9` | Main readable text |
| `textSecondary` | `#9B9BA6` | Labels, metadata |
| `textDisabled` | `#4E4E58` | Disabled/placeholder |
| `success` | `#10B981` | Emerald — savings, on-time |
| `warning` | `#F59E0B` | Amber — risk, delayed |
| `error` | `#EF4444` | Red — penalties, critical |
| `info` | `#60A5FA` | Blue — scheduled, informational |
| `verdictAction` | `#8B5CF6` | Violet — verdict buttons ONLY (INV-23) |
| `neutral` | `#64748B` | Completed, inactive |
| `superAdminSurface` | `#1E1B4B` | SuperAdmin mode indicator |

**Forbidden:** pure-white backgrounds, generic AI aesthetics, vibrant non-semantic colors.
**Semantic financial coloring:** Emerald (Savings), Red (Penalties), Amber (Risk).

### 2. Token Classes (Dart)

```dart
VeraProbColors   // color tokens (above)
VeraProbSpacing  // 8pt grid: xs=4, sm=8, md=16, lg=24, xl=32, xxl=48
VeraProbRadii    // border radius: sm=4, md=8, lg=12, xl=16, pill=999
VeraProbMotion   // duration: fast=150ms, base=200ms, slow=300ms; curve=easeOutCubic
VeraProbBreakpoints  // compact=600, medium=900, wide=1100, maxContent=1600
VeraProbElevation    // flat=[], raised=[…], overlay=[…]
VeraProbTypography   // text styles: base (Inter), heading (Outfit), mono, kpiValue, etc.
```

### 3. Layout & Typography

- **Grid:** Strict 8pt spacing system via `VeraProbSpacing`.
- **Typography:** Inter (UI elements), Outfit (headings/KPIs). Never browser defaults.
- **Breakpoints:** `compact < 600 < medium < 900 < wide < 1100`. Use `VeraProbBreakpoints.isCompact(ctx)`.
- **Icons:** Outlined, 20px/24px standard. `Icons.*_outlined` preferred.
- **Max content width:** 1600px.

### 4. Component Patterns

- **Borders:** 1px `border` color. No drop shadows on flat surfaces.
- **Radius:** Always `VeraProbRadii.*` — never raw `BorderRadius.circular()`.
- **Cards:** `surface` fill + `border` side. Elevation only via `VeraProbElevation.raised` on hover/focus.
- **Glassmorphism:** Subtle — `surfaceElevated` + `border` + `overlay` elevation on modals.

### 5. Micro-interactions

- **Feedback:** Immediate visual confirmation for all actions.
- **Animations:** Use `VeraProbMotion.base` (200ms) as default; `fast` for micro-hover; `slow` for modals.
- **Curve:** `VeraProbMotion.curve` = `Curves.easeOutCubic`.
- **Empty States:** `EmptyState` widget — icon + title + description + optional action.

### 6. Accessibility

- **Contrast:** WCAG AA minimum 4.5:1 (text) / 3:1 (UI glyphs). Validate all Indigo Zinc pairs.
- **Accent fills:** foreground on `primary`/`secondary`/`error` fills is ALWAYS `background` (dark), never `Colors.white`. White fails AA on every Indigo Zinc accent (primary 3.6:1, secondary 1.5:1, error 3.8:1); `background` passes (5.5:1 / 13:1 / 5.2:1). Encoded in `colorScheme.onPrimary/onSecondary/onError` and `ElevatedButtonTheme` — never override back to white at widget level. Recipe: `.claude/rules/ci-blocks.md` #18 (ACCENT-FILL-CONTRAST).
- **New token pairs:** validate BOTH directions before commit — token-as-fill with its foreground AND token-as-text on `background`/`surface`.
- **Touch:** Minimum 44×44pt hit targets.
- **Focus:** Clear, high-visibility focus rings (primary color @ 40% opacity).

### 7. Code Rules

- Never use `Colors.*` raw — use `VeraProbColors.*`.
- Never use inline `TextStyle(...)` — use `VeraProbTypography.*` or `Theme.of(context).textTheme.*`.
- Never use `BorderRadius.circular(n)` with a literal — use `VeraProbRadii.*`.
- Use `VeraProbBreakpoints.isCompact(context)` for responsive layout decisions.
- No IIFE in widget trees (IIFE-UI-SMELL). No raw exceptions in UI (UX-RAW-EXCEPTION).
