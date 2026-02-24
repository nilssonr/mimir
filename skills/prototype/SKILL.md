---
name: prototype
description: Visual prototyping loop for UI features. Screenshots the current page, proposes concrete change options, injects CSS prototypes via Volundr, and iterates with user feedback until visual direction is locked. Writes visual-decisions.md for Freya. Requires Chrome DevTools MCP or Playwright MCP configured in the project.
disable-model-invocation: true
allowed-tools: Read, Bash, Task, TeamCreate, TeamDelete, SendMessage, AskUserQuestion
argument-hint: [page URL and what to improve, e.g. "localhost:3000/login — feels bland and generic"]
---

# Prototype

You are running a visual prototyping session. Your job is to help the user iterate on the look and feel of a specific page or component — using live CSS injection and screenshots — until the direction is locked. Then write the decisions so Freya can produce a precise interaction spec.

## Core Disciplines

1. **Screenshot before anything.** The first thing the user sees is their current page. Ground all discussion in what's on screen.
2. **Options before prototypes.** Present named, concrete changes. The user selects. Then prototype. Never prototype from assumptions.
3. **Never inject what the user didn't select.** No extras, no "improvements," no assumptions about what they meant.
4. **Per-element feedback.** Ask "keep A, drop B, adjust C" — not "do you like it?"
5. **Max 3 rounds.** Initial prototype + 2 refinements. If the user is still unhappy, that's a signal the design direction needs rethinking — redirect to `/mimir:design-direction`.

## Step 1: Resolve paths

```bash
PROJECT_SLUG=$(pwd | sed 's|/|-|g' | sed 's|^-||')
STATE_DIR=~/.claude/state/mimir/$PROJECT_SLUG
MEMORY_PATH=~/.claude/projects/$(pwd | sed 's|/|-|g')/memory
[ -d "$MEMORY_PATH" ] || MEMORY_PATH=""
MIMIR_DIR=${CLAUDE_PLUGIN_ROOT:-$(for d in ~/Code/nilssonr/mimir ~/Code/*/mimir ~/.claude/plugins/cache/mimir; do [ -f "$d/agents/odin.md" ] && echo "$d" && break; done 2>/dev/null)}
mkdir -p $STATE_DIR
```

**Guard:** If MEMORY_PATH is empty, stop: "No project memory found. Run Huginn first to initialize memory."

## Step 2: Check prerequisites

### Design direction

```bash
DESIGN_DIR=$MEMORY_PATH/design-direction.md
[ -f "$DESIGN_DIR" ] && echo "direction:yes" || echo "direction:no"
```

If no design direction exists: warn the user. "No design direction found. Prototyping without direction means I'll propose changes based on general best practices rather than your project's design language. Consider running `/mimir:design-direction` first for better results."

AskUserQuestion (header: "Design direction"):
- **Proceed without direction** — prototype from general design principles
- **Run `/mimir:design-direction` first** — establish direction, then come back

If "Run `/mimir:design-direction` first": stop here. Return: "Run `/mimir:design-direction` to establish your design language, then re-run `/mimir:prototype`."

If direction exists: read `$DESIGN_DIR`. Note the Philosophy, Personality traits, Visual Language, and Verifiable Rules. These constrain what options you propose — never propose changes that violate the direction.

### Page URL

If `$ARGUMENTS` includes a URL (contains `localhost`, `127.0.0.1`, or `http`): extract it as `PAGE_URL`. The rest of $ARGUMENTS is the user's intent.

If no URL in `$ARGUMENTS`: AskUserQuestion: "Which page should I prototype? Provide the dev server URL (e.g., localhost:3000/login)."

If no intent in `$ARGUMENTS`: AskUserQuestion: "What's bothering you about this page? Even a vague feeling is fine — 'it feels bland', 'the hierarchy is off', 'it doesn't look professional'."

Store: `PAGE_URL` and `USER_INTENT`.

## Step 3: Spawn Volundr for visual work

Volundr handles all browser interaction — screenshots, CSS injection, visual analysis. Keep one instance alive for the entire session.

```
TeamCreate: name=$PROJECT_SLUG-prototype
Task: subagent_type=mimir:volundr, team_name=$PROJECT_SLUG-prototype, name=volundr
Prompt: "You are in PROTOTYPE MODE. You are NOT implementing a feature. You are prototyping visual changes via live CSS injection.

Your job:
1. When asked to screenshot: navigate to the URL, take a screenshot, describe what you see (layout, typography, colors, spacing, interactive elements, visual hierarchy)
2. When asked to inject CSS: use Chrome DevTools evaluate_script to add a <style> tag with the specified CSS. Use id='mimir-prototype' so it can be found and replaced. Then take a screenshot and describe what changed.
3. When asked to reset: remove the style tag (evaluate_script: document.getElementById('mimir-prototype')?.remove()) and confirm.

DO NOT modify any files. All changes are runtime CSS injection only — ephemeral, browser-only.
DO NOT add changes the team lead didn't ask for. Apply EXACTLY what's requested, nothing more.

Wait for instructions via SendMessage from team-lead."
```

## Step 4: Initial screenshot

Send to Volundr:

```
"Navigate to {PAGE_URL} and take a screenshot. Describe what you see:
- Overall layout and structure
- Typography (heading sizes, weights, font choices)
- Colors (background, text, accents, borders)
- Spacing (padding, margins, density)
- Interactive elements (buttons, inputs, links)
- Visual hierarchy (what draws attention first, second, third)

Do not change anything. Just observe and report."
```

Wait for Volundr's analysis.

Present to the user: "Here's what's on screen now:" followed by Volundr's description of the current page. Then state: "You said: '{USER_INTENT}'. Let me propose some concrete changes."

## Step 5: Propose options

Based on Volundr's page analysis, the user's intent, and the design direction (if it exists), compose 4-6 named change options. Each option is:
- A single-letter label (A through F)
- A short name (2-4 words)
- A one-sentence description of the change
- Specific enough to implement as CSS but general enough to evaluate as a direction

**Good options** (concrete, singular):
- A: Bold heading — Increase main heading to 2.5rem extrabold
- B: Tighter form — Reduce input spacing from 24px to 16px gaps
- C: Accent button — Primary action gets brand color fill instead of outline
- D: Muted labels — Form labels to text-muted-foreground, smaller size
- E: Card elevation — Wrap form in a subtle card with shadow-sm

**Bad options** (vague, compound):
- "Make it look more modern" (not actionable)
- "Redesign the form and add a logo and change colors" (3 changes in 1)
- "Add some visual interest" (what does that mean as CSS?)

Every option must be traceable to either: the user's stated intent, or an observation from the page analysis. Never propose changes from assumptions about what "looks good."

If design direction exists: constrain options to what the direction permits. If the direction says "density: spacious", don't propose "tighter form." If the direction says "typography: neutral", don't propose "expressive display font."

Present options via AskUserQuestion (multiSelect: true, header: "Changes"):

The question text: "Here are concrete changes I can prototype. Select the ones you want to see applied together:"

Options (use actual option labels):
- Each option as a selectable item with the name as label and description as description

## Step 6: Prototype loop

Track iteration count. Start at 1.

### Apply selected options

Compose CSS for the selected options. Send to Volundr:

```
"Inject this CSS into the page at {PAGE_URL}. Use a <style> tag with id='mimir-prototype'.

CSS:
{composed CSS for all selected options}

Then take a screenshot and describe what changed compared to the original. List each change by its option letter."
```

Wait for Volundr's response.

### Present result

Present Volundr's description to the user. Frame as per-element feedback:

"Prototype applied. Here's what changed:
- **A (Bold heading)**: {Volundr's description of this change}
- **C (Accent button)**: {Volundr's description of this change}

For each change, tell me: keep, drop, or adjust?"

AskUserQuestion (header: "Prototype"):
- **Looks good — lock this direction** (Recommended after iteration ≥ 2)
- **Adjust — I'll say what to change**
- **Start over — these options missed the mark**

### If "Looks good"

Break to Step 7.

### If "Adjust"

Ask: "What should I change? For each element, say keep/drop/adjust (and how)."

Wait for user's per-element feedback. Increment iteration count.

**If iteration count > 3:** Tell the user: "We've done 3 rounds. If the direction still feels wrong, the issue might be upstream — your design direction, not this specific prototype. Consider running `/mimir:design-direction` to rethink the foundation."

AskUserQuestion (header: "Next step"):
- **One more round** — apply the adjustments
- **Rethink direction** — stop here, revisit design direction
- **Accept current state** — lock what we have

If "One more round" and iteration count ≤ 3: compose updated CSS from keep/drop/adjust feedback. Send reset + new CSS to Volundr. Return to "Present result."

### If "Start over"

Send reset to Volundr: "Reset: remove the prototype style tag. Confirm when done."

Return to Step 5 with a fresh set of options informed by what the user rejected. State: "Understood — those didn't work. Let me propose a different direction." Compose new options that do NOT repeat the rejected ones.

This "start over" is allowed once. If the user rejects the second set of options: "Two sets of options rejected. The issue is likely upstream. Run `/mimir:design-direction` to establish a clear foundation first."

## Step 7: Write visual decisions

Compile the locked decisions into a structured document. For each accepted change, record:
- Option letter and name
- The CSS property/value applied
- The design rationale (traced to user intent or direction)

Write to `$STATE_DIR/visual-decisions.md`:

```markdown
# Visual Decisions: {page name}

Page: {PAGE_URL}
Date: {today}
Design direction: {exists/absent}
Iterations: {count}

## Locked Changes

### {A: Option name}
- **What**: {description of the visual change}
- **CSS**: `{property}: {value}`
- **Rationale**: {user's stated intent or direction trait this serves}

### {C: Option name}
...

## Rejected Options
{List any options the user explicitly dropped, with the reason if stated. Helps Freya avoid re-proposing them.}

## User Intent
"{USER_INTENT}" — original statement that started this session.
```

## Step 8: Shutdown and return

Shutdown Volundr:
```
SendMessage: teammate=volundr, type=shutdown_request
Wait for shutdown_response. TeamDelete: name=$PROJECT_SLUG-prototype
```

Present the final locked decisions to the user.

Return: "Visual decisions locked at $STATE_DIR/visual-decisions.md. {N} changes confirmed after {iteration count} round(s). Ready for Freya — run your feature task and the pipeline will pick up these decisions."
