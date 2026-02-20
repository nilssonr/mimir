# Mimir Design Document

## Vision

Memory-first agent orchestration for Claude Code. The lead coordinates on demand, teammates execute, shared memory persists knowledge across sessions.

Named after the Norse guardian of the Well of Wisdom -- all agents drink from shared memory.

## Core Principles

1. **Lead is opt-in, not always-on** -- invoke `/mimir:lead` when you need orchestration. Default Claude for everything else.
2. **Memory is the shared well** -- project knowledge written once, auto-loaded for every session (lead and teammates)
3. **File-based state over conversation state** -- everything that matters is persisted to disk
4. **Ephemeral teammates** -- spawn per task, write results to files, exit. No long-lived sessions accumulating tokens
5. **No duplicate work** -- Orienter runs only when memory is stale (git hash tracking), no agent re-discovers what memory already knows
6. **AskUserQuestion for all decisions** -- every question to the user uses structured options. No freeform questions in prose.

## Architecture

### Lead Protocol (agents/lead.md)

Activated via CLI: `claude --agent mimir:lead --plugin-dir ~/Code/nilssonr/mimir`. The lead is the session's system prompt from the start. It classifies user intent, checks memory freshness when codebase knowledge is needed, proposes teams, and manages the lifecycle. Not all tasks need teams -- discussions and opinions are answered directly.

Evolution: Started as CLAUDE.md (not a plugin component) -> agents/lead.md as default agent via settings.json (always-on, model ignored its protocol) -> skills/lead/SKILL.md (opt-in mid-session, but weaker than system prompt) -> agents/lead.md with `--agent` CLI flag (opt-in at launch, full system prompt strength).

Usage:
```bash
# Normal session, no orchestration
claude --plugin-dir ~/Code/nilssonr/mimir

# Lead session, ready to coordinate
claude --agent mimir:lead --plugin-dir ~/Code/nilssonr/mimir

# Or with alias
alias mimir="claude --agent mimir:lead --plugin-dir ~/Code/nilssonr/mimir"
```

### Memory Freshness (git-based)

The Orienter writes `.orienter-state` alongside memory files:
```
commit: <hash>
branch: <branch>
dirty: <true|false>
timestamp: <ISO 8601>
```

The lead compares stored state against current git state to assess freshness:
- Same hash + clean tree + same branch -> FRESH, skip orientation
- Minor drift (< 10 files changed) -> proceed with existing memory
- Major drift (> 30 files, branch switch) -> recommend re-orientation
- No state file -> AskUserQuestion: orient or trust existing memory?

Orientation is a dependency resolved on demand, not a session preamble.

### Teammates (own context, write files/memory, can communicate)

| Role | Agent file | Model | Purpose | Writes to |
|---|---|---|---|---|
| Orienter | orienter.md | sonnet | Learn project, populate memory | memory/*.md, memory/.orienter-state |
| Planner | planner.md | sonnet | Explore codebase, write implementation plan with dependency tags | specs/{org}/{repo}/{feature-slug}.md |
| Implementer | implementer.md | sonnet | TDD cycle per module, own worktree | code + tests, memory/conventions.md |
| Validator | validator.md | sonnet | Acceptance test against SPEC | state/{task}/validation.md |
| Reviewer | reviewer.md | sonnet | Code review per lens, can debate | state/{task}/review.md |
| Investigator | investigator.md | sonnet | Debug hypothesis, can debate | state/{task}/findings.md |
| Researcher | researcher.md | sonnet | External knowledge acquisition | memory/ or state/{task}/research.md |

### Subagents (single-shot, result-only)

| Role | Model | Purpose |
|---|---|---|
| Enhancer | haiku | raw prompt + context -> enhanced prompt with scope/criteria/constraints |
| PR Composer | haiku | git log -> PR title + body |
| Retro Analyzer | haiku | log file -> ranked proposals |
| Synthesizer | sonnet | memory + requirements -> questions + SPEC |
| Auto-Retro | haiku | task history + git log -> process learnings -> memory/process.md |

### Memory Model

Project memory at `~/.claude/projects/{project}/memory/` is auto-loaded into every session's system prompt (MEMORY.md up to 200 lines, topic files linked from index).

Memory files:
- `stack.md` -- language, frameworks, versions, build tools
- `structure.md` -- directory layout, packages, modules, key files
- `conventions.md` -- error handling, test patterns, naming, DI
- `architecture.md` -- key abstractions, data flow, API patterns
- `domain.md` -- business entities, relationships, API surface
- `process.md` -- lessons learned from retros
- `.orienter-state` -- git hash, branch, dirty flag, timestamp

Memory is populated by the Orienter (on demand) and enriched by teammates after each task.

### File Protocol

| Artifact | Location | Lifecycle |
|---|---|---|
| Project memory | `~/.claude/projects/{project}/memory/` | Persistent, enriched over time |
| Orienter state | `~/.claude/projects/{project}/memory/.orienter-state` | Updated after each orientation |
| SPECs | `~/.claude/specs/{org}/{repo}/` | Per-feature, survives sessions |
| Task state | `~/.claude/state/{task-id}/result.md` | Per-task, archived after retro |

### Feature Lifecycle

```
ENHANCE   ->  lead scores prompt quality, spawns Enhancer subagent if vague
              user approves enhanced prompt via AskUserQuestion
CLASSIFY  ->  lead classifies approved prompt
              simple? -> skip to EXECUTE (single Implementer)
CHECK MEM ->  does this need codebase knowledge?
              yes -> CHECK MEMORY FRESHNESS -> orient if stale
PLAN      ->  Planner teammate explores codebase, writes plan file with dependency tags
              lead reads plan, presents parallelization to user
EXECUTE   ->  Implementer(s) in worktrees, parallel groups from plan
VALIDATE  ->  Validator reads SPEC + implementation, reports gaps
              gaps? -> loop back to EXECUTE
INTEGRATE ->  merge worktree branches, Reviewer examines combined diff
AUTO-RETRO -> subagent reviews what happened, updates memory/process.md
```

### Bug Lifecycle

```
CLASSIFY   -> obvious (single Implementer) or complex (competing hypotheses)
INVESTIGATE -> 2-3 Investigator teammates, different hypotheses, debate via messages
FIX        -> surviving hypothesis -> Implementer
VALIDATE   -> Validator confirms fix addresses original issue
```

## What This Replaces

Previously: claude-skills repo with Makefile symlinks, 9 agents, 12 skills, 6 hooks, 200+ line CLAUDE.md with all skill definitions loaded into lead context.

Problems solved:
- Context pollution (lead held everything)
- Token waste (re-discovery per agent, no shared memory)
- Monolithic skills (loaded as prompts into main context)
- Manual installation (Makefile symlinks)
- Always-on coordination tax (lead was default agent, even for casual sessions)

## Plugin Distribution

Mimir is a Claude Code plugin. Installed via `claude --plugin-dir` or `/plugin install` from marketplace. No Makefile, no symlinks.

Plugin structure:
```
mimir/
  .claude-plugin/plugin.json
  agents/
    lead.md                    -- lead coordinator (activated via --agent mimir:lead)
    orienter.md                -- project exploration teammate
  hooks/hooks.json + scripts/  -- enforcement hooks (not yet built)
  settings.json                -- {} (no default agent; lead is opt-in via --agent flag)
  monitoring/                  -- Docker Compose observability stack
```

OTel telemetry env vars live in `~/.claude/settings.json` (global), not the plugin. Plugin `settings.json` only supports the `agent` key.

## Monitoring

OpenTelemetry-based telemetry with:
- OTel Collector (with deltatocumulative processor) -> Prometheus (metrics) + Loki (logs)
- Grafana dashboard at localhost:3333
- Per-session token tracking (each teammate measured independently)
- Actual Claude Code metrics: `claude_code.cost.usage` (USD), `claude_code.token.usage` (tokens), `claude_code.active_time.total`

## Experiment Plan

### Experiment 1: Lead Skill + Orienter
- Invoke `/mimir:lead` in caser-ts, ask to orient
- Evaluate: does the lead classify correctly, check memory, spawn Orienter via Agent Teams?
- Evaluate: does the Orienter write quality memory files + .orienter-state?
- Measure: accuracy, completeness, token cost, team lifecycle (spawn/shutdown)

### Experiment 2: Enhancer + Planner Pipeline (tests prompt quality, plan precision -- confidence 0.40)
- Vague feature request through full pipeline: Enhance -> Classify -> Plan
- Evaluate: does the Enhancer improve classification accuracy? Does the Planner produce actionable plans with correct dependency tags?
- Measure: enhancement quality, plan precision, token cost for each stage

### Experiment 3: Parallel Implementers (tests H2, H3, H6 -- confidence 0.40-0.50)
- 2-module feature, Planner-generated plan, 2 Implementer teammates in separate worktrees
- Measure: spawn overhead, parallel speedup, merge friction, token cost

### Experiment 4: Validator (tests H5 -- confidence 0.50)
- After Experiment 3, spawn Validator against SPEC + implementation
- Measure: true/false positives, actionability

### Experiment 5: Full Pipeline (integration test, after 1-4 pass)

## Current State

### Built
- [x] Repository created at ~/Code/nilssonr/mimir
- [x] Plugin manifest (.claude-plugin/plugin.json)
- [x] Lead agent (agents/lead.md) activated via `--agent mimir:lead`
- [x] Orienter agent definition (agents/orienter.md) with .orienter-state
- [x] Enhancer agent definition (agents/enhancer.md) -- inline subagent for vague prompts
- [x] Planner agent definition (agents/planner.md) -- teammate for implementation plans
- [x] Lead protocol updated with Step 0 (prompt quality) and Planner integration in Step 3
- [x] Monitoring stack (docker-compose + OTel + Prometheus + Grafana)
- [x] Monitoring fixes: deltatocumulative processor, otlp_http/loki, Loki OTLP config
- [x] Dashboard with real Claude Code metric names
- [x] Telemetry env vars in ~/.claude/settings.json
- [x] claude-skills unlinked from ~/.claude/ (clean slate)

### Not Yet Built
- [ ] agents/implementer.md, validator.md, reviewer.md, investigator.md, researcher.md
- [ ] hooks/hooks.json and hook scripts
- [ ] Initial git commit

## Key Design Decisions

1. **Lead is opt-in via `--agent` flag** -- `claude --agent mimir:lead` activates orchestration. Without it, Claude is just Claude. Stronger than a skill (system prompt vs mid-session injection) and cleaner than a default agent (explicit opt-in at launch).
2. **Orienter replaces repo-scout + codebase-analyzer** -- single agent, no artificial constraints, writes directly to memory
3. **Git-based memory freshness** -- `.orienter-state` stores commit hash, branch, dirty state. The lead compares against current state to decide if re-orientation is needed. No redundant orientation.
4. **AskUserQuestion for all decisions** -- structured options, no freeform questions. Forces better classification and gives clean UX.
5. **Implementer merges RED + GREEN + REFACTOR** -- one teammate runs the full TDD cycle, not 3 separate agents
6. **Memory enrichment by teammates** -- convention discovery is a side-effect of doing work, not a separate phase
7. **Worktree isolation for parallel execution** -- each Implementer gets its own worktree, eliminates file conflicts
8. **Plugin distribution** -- no Makefile, no symlinks, proper Claude Code plugin system
9. **Telemetry from day one** -- OpenTelemetry with deltatocumulative conversion for Prometheus compatibility
10. **Enhancer as subagent, not teammate** -- prompt enhancement is fast, single-shot, and needs no codebase access. Haiku model for minimal cost.
11. **Planner as teammate, not subagent** -- plan quality requires codebase exploration (reading files, understanding patterns). Sonnet model for reasoning capability.
12. **Enhancement before classification** -- vague prompts cause misclassification. Enhancing first produces better routing and prevents backtracking loops.

## Confidence Assessment (overall: 0.55)

| Aspect | Confidence |
|---|---|
| Role decomposition | 0.85 |
| Lead via --agent flag (opt-in) | 0.75 |
| Memory as shared knowledge | 0.80 |
| Git-based memory freshness | 0.70 |
| File-based state | 0.80 |
| Ephemeral teammates cost-effective | 0.45 |
| Plan precision enabling parallelization | 0.40 |
| Validator catching real gaps | 0.50 |
| Memory enrichment by teammates | 0.35 |
| Agent Teams stability | 0.40 |
| Worktree management at scale | 0.50 |
