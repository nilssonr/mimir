---
name: design-system
description: Project-specific design system tokens, spacing, palette, and component patterns. Customize per project.
---

# Design System

This skill defines the project's design system. Customize the sections below for each project.

## Tokens

Read the project's design token files before writing any UI code. Common locations:
- `tailwind.config.*` or `@theme` block in CSS entry point
- `src/styles/tokens.*` or `src/theme.*`
- shadcn `components.json` for component configuration
- CSS custom properties in `:root` or `@layer base`

### Colors
Use the project's color tokens exclusively. Never introduce arbitrary hex/rgb values.
- Primary, secondary, accent, destructive
- Background, foreground, muted, card, popover
- Border, input, ring

### Typography
- Font families defined in the project
- Size scale (text-xs through text-4xl or custom)
- Weight scale (font-normal, font-medium, font-semibold, font-bold)
- Line height and letter spacing tokens

### Spacing
- Use the project's spacing scale (p-1 through p-12, or custom)
- Consistent gaps between components (gap-2, gap-4, gap-6)
- Section padding conventions

### Radii & Shadows
- Border radius tokens (rounded-sm, rounded-md, rounded-lg)
- Shadow tokens (shadow-sm, shadow-md)

## Component Patterns

Before creating a new component, check if the project already has:
- A similar component that can be extended
- A component library (shadcn/ui, Radix, etc.) with the needed primitive
- Established composition patterns (Card + CardHeader + CardContent, etc.)

### Conventions
- Follow the project's component naming convention (PascalCase, kebab-case, etc.)
- Match the established prop interface patterns
- Use the project's preferred state management approach
- Follow the established file/directory structure for components

## Accessibility

- All interactive elements must be keyboard accessible
- Color contrast must meet WCAG 2.1 AA (4.5:1 for text, 3:1 for large text)
- Use semantic HTML elements (button, nav, main, article)
- ARIA labels on icon-only buttons and non-obvious interactive elements
- Focus indicators must be visible

## Rules

- Read the existing design system before writing anything new
- Never override tokens with inline styles or arbitrary values
- When in doubt about a pattern, find an existing example in the codebase and follow it
- If the project has no design system yet, propose token definitions before implementing UI
