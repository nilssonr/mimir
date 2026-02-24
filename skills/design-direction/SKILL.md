---
name: design-direction
description: Establish or refine the project's design direction through research and multi-turn brainstorming. Creates or updates design-direction.md in project memory before UI feature planning begins.
disable-model-invocation: true
allowed-tools: Read, Bash, Task, TeamCreate, TeamDelete, SendMessage, AskUserQuestion
argument-hint: [feature description, or leave empty to manage direction standalone]
---

# Design Direction

You are managing the project's design direction. Your job is to establish or refine `design-direction.md` — the foundational document that Freya reads before every interaction spec. Work through research and multi-turn brainstorming until the user confirms a direction, then write it to project memory.

## Step 1: Resolve paths

```bash
PROJECT_SLUG=$(pwd | sed 's|/|-|g' | sed 's|^-||')
STATE_DIR=~/.claude/state/mimir/$PROJECT_SLUG
MEMORY_PATH=~/.claude/projects/$(pwd | sed 's|/|-|g')/memory
[ -d "$MEMORY_PATH" ] || MEMORY_PATH=""
MIMIR_DIR=${CLAUDE_PLUGIN_ROOT:-$(for d in ~/Code/nilssonr/mimir ~/Code/*/mimir ~/.claude/plugins/cache/mimir; do [ -f "$d/agents/odin.md" ] && echo "$d" && break; done 2>/dev/null)}
DESIGN_DIR=$MEMORY_PATH/design-direction.md
mkdir -p $STATE_DIR
```

**Guard:** If MEMORY_PATH is empty after the above block, stop immediately with this error message: "Cannot run design-direction skill: no project memory directory found. Run Huginn first to initialize memory." Do not proceed — DESIGN_DIR would be a broken relative path (`design-direction.md`) that silently writes to the wrong location.


## Step 2: Check for existing design-direction.md

```bash
DIRECTION_EXISTS=$([ -f "$DESIGN_DIR" ] && echo "yes" || echo "no")
```

## Step 3A: Missing direction (DIRECTION_EXISTS=no)

Tell the user: "No design direction found — researching before we brainstorm."

Read the relevant memory files to populate `Established`: read `domain.md`, `decisions.md`, and `stack.md` from `$MEMORY_PATH` if they exist.

Spawn Bragi (team lifecycle):

```
TeamCreate: name=$PROJECT_SLUG-direction
Task: subagent_type=mimir:bragi, team_name=$PROJECT_SLUG-direction, name=bragi
Prompt: "Topic: Design direction appropriate for this project's domain, users, and technical context

Established:
{relevant facts from domain.md and decisions.md — project type, intended users, any prior design decisions}

Investigate:
- Visual design language appropriate for this project's domain and users
- Typography, color palette, motion, and density conventions that fit the context
- Component character: how buttons, forms, cards, navigation, and feedback should feel
- 2-3 reference products that demonstrate the right qualities for this project

Purpose: Produce a draft design-direction.md using the exact format Freya requires (Philosophy, Personality, Visual Language, Verifiable Rules, Constraints, Component Character — see $MIMIR_DIR/agents/freya.md lines 22-57 for the required schema).

Constraints: {stack from stack.md}
Depth: deep
Output: $DESIGN_DIR"

[wait for completion]

SendMessage: teammate=bragi, type=shutdown_request
Wait for shutdown_response. TeamDelete: name=$PROJECT_SLUG-direction
```

Bragi writes the full draft design-direction.md to `$DESIGN_DIR`. After Bragi shutdown: check that `$DESIGN_DIR` exists and is non-empty. If absent or empty: tell the user "Bragi failed to write a design direction draft. Check the team output and retry." Stop. Otherwise: read `$DESIGN_DIR`, present a one-paragraph summary to the user (Philosophy + 3 Personality traits). Then proceed to **Step 4** (brainstorming loop).

## Step 3B: Existing direction (DIRECTION_EXISTS=yes)

Read `$DESIGN_DIR`. Present a one-paragraph summary: Philosophy + 3 Personality traits.

AskUserQuestion with header "Direction":
- **Review**: "Validate against current feature scope — report alignment gaps"
- **Revise**: "Update or refine the direction through brainstorming with Freya"
- **Extend**: "Add new aspects through brainstorming with Freya"

**Review path:** Read `$ARGUMENTS` (feature description if passed). Analyze the existing design-direction.md against the feature context. Report: "Direction alignment: [strong/partial/misaligned]. Gaps: [list]." No Freya spawn. Return: "design-direction.md ready at {DESIGN_DIR}."

**Revise or Extend paths:** Proceed to **Step 4** (brainstorming loop).

## Step 4: Brainstorming loop

Track the evolving direction text in `$STATE_DIR/direction-draft.md`. Copy the current `$DESIGN_DIR` content there as the starting draft, then update it after each Freya exchange so each message to Freya includes the latest state.

Compose the initial message to Freya:
- **New direction (after Bragi):** "Review and critique the draft design-direction.md I've written to {DESIGN_DIR}. Propose refinements, flag anything inconsistent or missing. Respond with specific proposed direction statements — not a UX spec. You are operating in design direction brainstorming mode: help shape design-direction.md, not ux-spec.md."
- **Revise:** "Review the current design-direction.md at {DESIGN_DIR} and propose targeted revisions. Focus area: [user's stated focus from $ARGUMENTS or AskUserQuestion]."
- **Extend:** "Review the current design-direction.md at {DESIGN_DIR} and propose additions for: [user's stated aspect from $ARGUMENTS or AskUserQuestion]."

Spawn Freya (team lifecycle):

```
TeamCreate: name=$PROJECT_SLUG-direction-loop
Task: subagent_type=mimir:freya, team_name=$PROJECT_SLUG-direction-loop, name=freya
Prompt: "You are operating in design direction brainstorming mode. Do NOT produce a UX interaction spec. Do NOT produce anything yet — wait for a message from team-lead with the current direction draft before responding. Memory path: $MEMORY_PATH
Note: This skill is Odin-only — the team lead is always addressable as 'team-lead'."
```

SendMessage to freya: {initial brainstorming message, including the full current draft from $STATE_DIR/direction-draft.md}

Loop:
1. Wait for Freya's response via SendMessage
2. Write Freya's proposed changes to `$STATE_DIR/direction-draft.md` (merge proposals into the current draft)
3. Present Freya's proposals to the user
4. AskUserQuestion (header: "Design direction"):
   - "Happy with this direction — confirm and write" (Recommended after ≥1 round)
   - "Keep refining — send feedback to Freya"
5. If "Keep refining": send user feedback + the current draft + "Please propose next round of refinements" to Freya via SendMessage. Go to 1.
6. If "Confirm": break out of loop.

Shutdown Freya:
```
SendMessage: teammate=freya, type=shutdown_request
Wait for shutdown_response. TeamDelete: name=$PROJECT_SLUG-direction-loop
```

## Step 5: Write confirmed direction

Present the final direction (from `$STATE_DIR/direction-draft.md`) to the user for one last review. Write it to `$DESIGN_DIR`.

Verify the written file contains all required sections: Philosophy, Personality, Visual Language, Verifiable Rules, Constraints, Component Character.

Return: "design-direction.md ready at {DESIGN_DIR}."
