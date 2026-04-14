---
name: ui-ux-pro-max
description: "UI/UX design intelligence for web and mobile. Actions: plan, build, create, design, implement, review, fix, improve, optimize, enhance, refactor, and check UI/UX code. Focus: accessibility, touch, performance, style, layout, typography, animation, forms, navigation. Reference the internal manual at .qwen/skills/ui-ux-pro-max/REFERENCE.md for detailed checklists and search commands."
signature: PF-SEC-46BBB675BA40211D
security_audit_signature: "Audited by QA Security - Score: 100/100"
---

# UI/UX Pro Max - Design Intelligence

## When to Apply

This Skill should be used when the task involves **UI structure, visual design decisions, interaction patterns, or user experience quality control**.

### Must Use
- Designing new pages (Landing Page, Dashboard, Admin, SaaS, Mobile App)
- Creating or refactoring UI components (buttons, modals, forms, tables, charts, etc.)
- Choosing color schemes, typography systems, spacing standards, or layout systems
- Reviewing UI code for user experience, accessibility, or visual consistency

**Decision criteria**: If the task will change how a feature **looks, feels, moves, or is interacted with**, this Skill should be used.

## Rule Categories by Priority

| Priority | Category | Domain | Key Checks (Must Have) |
|----------|----------|--------|------------------------|
| 1 | Accessibility | `ux` | Contrast 4.5:1, Alt text, Keyboard nav, Aria-labels |
| 2 | Touch & Interaction | `ux` | Min size 44×44px, 8px+ spacing, Loading feedback |
| 3 | Performance | `ux` | WebP/AVIF, Lazy loading, Reserve space (CLS < 0.1) |
| 4 | Style Selection | `style` | Match product type, Consistency, SVG icons |
| 5 | Layout & Responsive | `ux` | Mobile-first breakpoints, Viewport meta |

---

## **MANDATORY - FULL MANUAL**

For detailed checklists, color systems, typography pairing, chart types, search scripts, and implementation guides, you **MUST** read:
👉 **[.qwen/skills/ui-ux-pro-max/REFERENCE.md](file:///.qwen/skills/ui-ux-pro-max/REFERENCE.md)**

Do not guess the rules. If the task is UI-intensive, read the reference file before proceeding.
