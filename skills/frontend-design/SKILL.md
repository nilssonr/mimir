---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Anti-slop guidelines for typography, color, motion, and composition.
---

# Frontend Design

Create distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics.

## Pre-Build Checklist

Before writing ANY component markup:

### 1. Reference Existing Patterns
- If the project uses shadcn/ui, query the MCP server FIRST for component examples and variants
- Read existing pages/components for established token usage (colors, spacing, typography)
- Use official demos + codebase patterns as the structural baseline, then customize

### 2. Verify CSS Foundation
For Tailwind CSS v4 + shadcn/ui projects, verify in the CSS entry point:
- `@layer base { * { border-color: var(--color-border) } }` — without this, all borders use currentColor
- `body { background-color: var(--color-background); color: var(--color-foreground) }`
- Design tokens properly mapped in `@theme inline { }`

If a visual issue involves color or contrast, check the CSS foundation FIRST. Trace the cascade, don't guess.

### 3. Review Design Tokens
- Read the project's token files (colors, typography, spacing, radii, shadows)
- Use established conventions (e.g., `font-semibold` not `font-bold`, `text-muted-foreground` for secondary)
- Never introduce arbitrary color/spacing values when tokens exist

## Design Thinking

Before coding, commit to a BOLD aesthetic direction:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Commit to a distinct direction. Infinite varieties: brutally minimal, maximalist, luxury/refined, lo-fi/zine, dark/moody, soft/pastel, editorial, brutalist, retro-futuristic, handcrafted, organic, art deco, playful, industrial.
- **Constraints**: Framework, performance, accessibility requirements.
- **Differentiation**: What's the one thing someone will remember?

## Aesthetics Guidelines

### Typography
Choose fonts with personality. Default fonts signal default thinking — skip Arial, Inter, Roboto, system stacks. Display type: expressive, even risky. Body text: legible, refined. Work the full range: size, weight, case, spacing for hierarchy.

### Color & Theme
Commit to a cohesive palette. Lead with a dominant color, punctuate with sharp accents. Avoid timid, non-committal distributions. Use CSS variables for consistency.

### Motion
Prioritize CSS-only for HTML, Motion library for React. Focus on high-impact moments: one well-orchestrated page load with staggered reveals creates more delight than scattered micro-interactions. Scroll-triggered animations and hover states that surprise.

### Spatial Composition
Unexpected layouts. Asymmetry. Overlap and z-depth. Diagonal flow. Grid-breaking elements. Dramatic scale jumps. Full-bleed moments. Generous negative space OR controlled density.

### Visual Details
Gradient meshes, noise overlays, geometric patterns, layered transparencies, dramatic shadows, parallax depth, decorative borders, clip-path shapes, print-inspired textures, knockout typography, custom cursors.

## Anti-Slop Rules

NEVER use:
- Overused font families (Inter, Roboto, Arial, Space Grotesk, system fonts)
- Cliched color schemes (purple gradients on white backgrounds)
- Predictable layouts and cookie-cutter component patterns
- Generic designs that lack context-specific character

INSTEAD: Distinctive fonts. Bold, committed palettes. Layouts that surprise. Bespoke details. Every choice rooted in context.

## Rules

- Match implementation complexity to the aesthetic vision
- Maximalist designs need elaborate code with extensive animations
- Minimalist designs need restraint, elegance, and precision
- All designs need careful attention to spacing, typography, and subtle details
- Use the Chrome DevTools MCP to verify visual output. Take screenshots, self-correct, iterate.
