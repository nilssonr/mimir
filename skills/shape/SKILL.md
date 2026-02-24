---
name: shape
description: Guided multi-agent brainstorming session for vague or unarticulated tasks. Use when you don't know what you want to build yet, have a fuzzy direction but no concrete spec, or want to explore and research before committing to a pipeline run. Checks memory freshness first (spawns Huginn if stale), then shapes the idea through Loki, then optionally researches unknowns through Bragi. Hands off a confirmed, specific prompt directly into the pipeline.
disable-model-invocation: true
allowed-tools: Read, Bash, Task, TeamCreate, TeamDelete, SendMessage, AskUserQuestion
argument-hint: [rough idea, or leave empty to start from scratch]
---

# Shape

You are running a guided brainstorming session. Your job is to help the user discover and articulate what they want to build — using project memory, Loki for prompt shaping, and Bragi for research. Work iteratively until the user is confident. Then hand the confirmed prompt into the pipeline.

## Step 1: Resolve paths

```bash
PROJECT_SLUG=$(pwd | sed 's|/|-|g' | sed 's|^-||')
STATE_DIR=~/.claude/state/mimir/$PROJECT_SLUG
MEMORY_PATH=$(find ~/.claude/projects/*/memory -maxdepth 0 -type d 2>/dev/null | head -1)
MIMIR_DIR=${CLAUDE_PLUGIN_ROOT:-$(for d in ~/Code/nilssonr/mimir ~/Code/*/mimir ~/.claude/plugins/cache/mimir; do [ -f "$d/agents/odin.md" ] && echo "$d" && break; done 2>/dev/null)}
mkdir -p $STATE_DIR
```

## Step 2: Check memory freshness

```bash
ORIENTER_STATE=$(find ~/.claude/projects/*/memory/.huginn-state 2>/dev/null | head -1)
CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null)
```

Read `.huginn-state`. Compare `commit:` to `CURRENT_HEAD`.

**If mismatch or file missing:** Tell the user: "Memory is out of date — running Huginn before we start." Spawn Huginn (team lifecycle):

```
TeamCreate: name=$PROJECT_SLUG-shape-orient
Task: subagent_type=mimir:huginn, team_name=$PROJECT_SLUG-shape-orient, name=huginn
Prompt: "$(pwd)"

[wait for completion]

SendMessage: teammate=huginn, type=shutdown_request
Wait for shutdown_response. TeamDelete: name=$PROJECT_SLUG-shape-orient
```

If Agent Teams unavailable: `Task(subagent_type=mimir:huginn, prompt="$(pwd)")`

**If fresh:** proceed silently.

## Step 3: Gather the rough idea

If `$ARGUMENTS` is empty:

Use AskUserQuestion: "What are you thinking about? A rough direction, a problem, a user need — even just a vibe is fine."

Otherwise proceed with `$ARGUMENTS` as the starting point.

## Step 4: Shape with Loki

Spawn Loki (team lifecycle):

```
TeamCreate: name=$PROJECT_SLUG-shape-loki
Task: subagent_type=mimir:loki, team_name=$PROJECT_SLUG-shape-loki, name=loki
Prompt: "{raw idea}" (append "\n\nMemory path: {MEMORY_PATH}" only if MEMORY_PATH is non-empty)

[wait for completion]

SendMessage: teammate=loki, type=shutdown_request
Wait for shutdown_response. TeamDelete: name=$PROJECT_SLUG-shape-loki
```

If Agent Teams unavailable: `Task(subagent_type=mimir:loki, prompt="{raw idea}")`
  (if MEMORY_PATH is non-empty: append `"\n\nMemory path: {MEMORY_PATH}"` — omit if MEMORY_PATH is empty)

Parse Loki's response:

- `SUFFICIENT:` — Present the prompt to the user for confirmation. Skip to Step 5.
- `ENHANCED:` — AskUserQuestion with both versions:
  ► Use enhanced (Recommended)
  ► Use original
  ► Adjust — ask what to change, re-run Loki with the adjustment appended
- `CLARIFY:` — Present Loki's questions to the user as-is. Wait for answers. Re-run Loki with the original idea + answers. If still `CLARIFY:` after the second run, proceed with best-effort shaped version and flag the open questions to the user.

## Step 5: Research loop (optional)

After shaping, AskUserQuestion: "Prompt is shaped. Want to dig into anything before planning?"

► Proceed to planning — hand off now
► Research something — I'll invoke Bragi
► Adjust the shaped prompt — return to Step 4

**If "Research something":** Ask what to investigate (one AskUserQuestion, free-text answer). Then read the relevant memory files to populate `Established`. Spawn Bragi:

```
TeamCreate: name=$PROJECT_SLUG-shape-research
Task: subagent_type=mimir:bragi, team_name=$PROJECT_SLUG-shape-research, name=bragi
Prompt: "Topic: {user's question}

Established:
{relevant facts from stack.md and domain.md that bear on the question}

Investigate:
- {specific unknown the user asked about}

Purpose: Deciding whether / how to build — {shaped prompt summary}

Constraints: {stack from stack.md}
Depth: quick
Output: $STATE_DIR/shape-research.md"

[wait for completion]

SendMessage: teammate=bragi, type=shutdown_request
Wait for shutdown_response. TeamDelete: name=$PROJECT_SLUG-shape-research
```

If Agent Teams unavailable: `Task(subagent_type=mimir:bragi, prompt="...")`

Read `$STATE_DIR/shape-research.md`. Present **Confidence**, **Key finding**, and **Synthesis** to the user. If Open questions flag an escalation need, offer to re-invoke Bragi at Standard or Deep depth.

AskUserQuestion:
► Proceed to planning
► Research something else
► Revise the shaped prompt based on what we learned — return to Step 4

Loop until the user selects "Proceed to planning."

## Step 6: Hand off

Present the final shaped prompt in a fenced code block, ready to read.

Tell the user: "Ready. Proceeding now."

**Proceed directly to Phase 1 (intent classification). Skip Phase 0 — Loki has already run during this /shape session.**
