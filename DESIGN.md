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
| Auto-Retro | haiku | task history + git log -> process learnings -> memory/process.md + architectural decisions -> memory/decisions.md |

### Agent Taxonomy

In the predecessor system (claude-skills), "skills" were monolithic markdown prompts loaded into the lead's context. The lead classified user intent, dispatched to a skill, and the skill ran phases in the main context window. This caused context pollution and meant the lead held every protocol.

In mimir, skills dissolve into agent definitions. A skill was always two things: a **protocol** (how to do the work) and **enforcement** (gates, validation). These map to different layers:

| Concept | claude-skills | mimir |
|---|---|---|
| Protocol | Skill markdown loaded into lead context | Agent definition (.md file) -- the teammate *is* the skill |
| Enforcement | Hooks + phase gates in skill | Hooks (same) + agent-internal gates |
| Routing | CLAUDE.md classification table | Lead classification in agents/lead.md |
| Reference material | Skill-specific doc files | Project memory or spawn prompt context |

**Three tiers, not one:**

**Teammates** -- own context window, multi-step reasoning, codebase access, may collaborate or debate. Spawn overhead is justified by the complexity of the work. Examples: Orienter, Planner, Implementer, Reviewer, Investigator, Researcher.

Decision criteria: Does this need to explore code? Does it require multi-step reasoning? Will it produce artifacts through iterative work? If yes to any, teammate.

**Subagents** -- single-shot transformation. Known input shape, structured output, no codebase access, no collaboration. Cheap models (haiku) where reasoning demands are low. Examples: Enhancer, PR Composer, Retro Analyzer, Synthesizer, Auto-Retro.

Decision criteria: Can the input and output be fully specified in the spawn prompt? Is it a pure function (input -> output, no side-channel exploration)? If yes to both, subagent.

**Hooks** -- event-triggered side-effects. No reasoning, no context window. Shell scripts that enforce constraints or automate mechanical steps. Examples: formatters, commit validators, test gates.

Decision criteria: Is this a deterministic check or transformation? Does it need zero reasoning? If yes, hook.

**The test:** When considering a new capability, ask: "Does this need its own context window and multi-step reasoning?" If no, it's a subagent or hook. If it doesn't even need an LLM, it's a hook.

### Conditional Dispatch (integration pattern)

Teammates are single-purpose. The Reviewer reviews code -- it doesn't know or care about bug trackers. The Implementer writes code -- it doesn't file tickets. External integrations are the Lead's responsibility, dispatched conditionally based on teammate output + project memory.

**Pattern:**

```
Teammate produces output -> writes to state file
Lead reads output -> evaluates conditions (e.g., critical findings in review)
Lead checks memory/integrations.md -> determines target system
Lead spawns integration subagent with output + config -> subagent executes
```

**Example -- bug filing after review:**

```
Reviewer -> state/{task}/review.md (includes critical findings)
Lead reads review -> sees severity:critical
Lead reads memory/integrations.md -> bug_tracker: azure_devops, project: Backend
Lead spawns bug-filer subagent (haiku) with findings + azure config
Subagent runs az boards work-item create -> returns work item URL
```

Different project, different memory:

```
memory/integrations.md:
  bug_tracker: github_issues
  repo: org/frontend
  labels: ["bug", "from-review"]
```

Same Lead logic, same bug-filer subagent (parameterized by tracker type), different project config. The Reviewer never changes.

**Why this matters:**
- Teammates stay single-purpose and reusable across projects
- Project-specific behavior lives in memory, not agent definitions
- New integrations are additive (new subagent or new template) -- no existing agents modified
- The Lead is the only component that reads teammate output and decides next steps

### Memory Model

Project memory at `~/.claude/projects/{project}/memory/` is auto-loaded into every session's system prompt (MEMORY.md up to 200 lines, topic files linked from index).

Memory files:
- `stack.md` -- language, frameworks, versions, build tools
- `structure.md` -- directory layout, packages, modules, key files
- `conventions.md` -- error handling, test patterns, naming, DI
- `architecture.md` -- key abstractions, data flow, API patterns
- `domain.md` -- business entities, relationships, API surface
- `decisions.md` -- architectural decision record. Why we chose X over Y, what was considered and rejected. Appended by Auto-Retro after each feature. Read by Reviewer (and all teammates) to understand intent behind existing code.
- `process.md` -- lessons learned from retros
- `integrations.md` -- external system config (bug tracker, CI, notifications) used by Lead for conditional dispatch
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
              extracts architectural decisions (why X over Y) -> memory/decisions.md
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
- [x] Implementer agent definition (agents/implementer.md) -- TDD cycle, commits, reports back
- [x] Lead tool restrictions -- no direct codebase access, blocked fallback for missing roles
- [x] Monitoring stack (docker-compose + OTel + Prometheus + Grafana)
- [x] Monitoring fixes: deltatocumulative processor, otlp_http/loki, Loki OTLP config
- [x] Dashboard with real Claude Code metric names
- [x] Telemetry env vars in ~/.claude/settings.json
- [x] claude-skills unlinked from ~/.claude/ (clean slate)

### Not Yet Built
- [ ] agents/validator.md, reviewer.md, investigator.md, researcher.md
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
13. **Lead has no codebase tools** -- the lead may only use Bash for 3 git commands and Read for memory/plan files. All exploration and implementation goes through teammates. Prevents the lead from "just doing it" when permissions are wide open.
14. **Blocked fallback over improvisation** -- when a required role is undefined, the lead outputs a one-liner and stops. Better to surface the gap than to silently do the work itself.
15. **Skills dissolve into agent definitions** -- a skill was a protocol + enforcement. In mimir, the protocol becomes the agent's .md file (the teammate *is* the skill) and enforcement stays in hooks. No separate "skill invocation" step -- spawning the teammate activates the protocol.
16. **Conditional dispatch for integrations** -- teammates are single-purpose and project-agnostic. External integrations (bug filing, notifications, CI triggers) are dispatched by the Lead based on teammate output + project memory (integrations.md). New integrations are additive -- no existing agents modified.
17. **Three-tier agent taxonomy** -- teammates (own context, multi-step, codebase access), subagents (single-shot transformation, no codebase), hooks (deterministic, no LLM). The deciding question: "does this need its own context window?" If no, subagent or hook. If it doesn't need an LLM at all, hook.

## Confidence Assessment (overall: 0.60)

| Aspect | Confidence | Status |
|---|---|---|
| Role decomposition + three-tier taxonomy | 0.90 | Formalized with decision criteria. Experiment 1 confirmed teammate/subagent distinction. |
| Lead via --agent flag (opt-in) | 0.85 | Confirmed (Experiment 1). Classify -> check memory -> spawn teammate works. |
| Memory as shared knowledge | 0.85 | Confirmed (Experiment 1). Orienter wrote quality files. integrations.md extends pattern. |
| File-based state | 0.80 | Proven from claude-skills. Conditional dispatch reinforces (teammates write, lead reads). |
| Git-based memory freshness | 0.75 | Mechanism works (.orienter-state written correctly). Only one orientation run so far. |
| Skills-to-agents migration | 0.60 | Mapping is clear. Reference-heavy skills (sumo-search, temporal) lack a loading mechanism. |
| Ephemeral teammates cost-effective | 0.50 | One data point (Orienter). Acceptable overhead but no multi-teammate measurement. |
| Worktree management at scale | 0.50 | Untested. |
| Validator catching real gaps | 0.50 | Not built. |
| Agent Teams stability | 0.45 | Worked end-to-end but shutdown dance was awkward. Still experimental. |
| Plan precision enabling parallelization | 0.40 | Planner defined but never run. |
| Conditional dispatch (integrations) | 0.40 | Architecturally sound. Zero implementation. No subagent or integrations.md schema built. |
| Memory enrichment by teammates | 0.35 | Only Orienter (purpose-built). Will Implementers/Reviewers reliably enrich? Unknown. |
