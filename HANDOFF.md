# Mimir Handoff -- Session Context

Read this file to resume work on the mimir project. Read DESIGN.md after this for the full architecture spec.

## What This Project Is

Mimir is a from-scratch replacement for the claude-skills system. It's a Claude Code plugin that implements memory-first agent orchestration using Agent Teams.

The old system (claude-skills) used Makefile symlinks to install skills, agents, and hooks into ~/.claude/. Skills were monolithic markdown prompts loaded into the lead's context. Agents were subagents that reported results back to the lead. The lead held everything -- routing logic, phase gating, implementation details -- causing severe context pollution.

Mimir inverts this: the lead is a thin coordinator that never implements. Teammates (Agent Teams) do all execution. Shared project memory eliminates re-discovery.

## What We Learned (Chronological)

### 1. Agent Teams Audit (starting point)
We audited every agent, skill, and hook in claude-skills against Agent Teams capabilities. Key findings:
- Only 2 skills genuinely benefit from Agent Teams: review (large, parallel fan-out) and troubleshoot (competing hypotheses)
- Most skills are inherently sequential and should stay as subagents
- The review skill was the gold standard (0% context pollution, fully agent-delegated)
- troubleshoot was the worst offender (95% in main context)

### 2. Architecture Evolution
Started with three options for lead weight: heavy (current), selective teams, full delegation. User chose full delegation with lower token cost -- the hardest constraint.

Key insight from user: "with proper hand-off and delegated tasks, work doesn't have to get done twice." This led to:
- Shared reconnaissance artifacts that persist across agents
- Planning precise enough to enable parallel implementation
- TDD parallelized at the module level (each Implementer runs full RED-GREEN-REFACTOR)

### 3. Memory Model (user-driven insight)
User suggested using Claude's built-in memory feature (~/.claude/projects/{project}/memory/) instead of disk files for project knowledge. This was a better answer because:
- MEMORY.md is auto-loaded into every session's system prompt (including teammates)
- No "read this file" instructions needed in spawn prompts
- Crosses session boundaries naturally
- Already project-scoped

We split artifacts into memory (stable project knowledge) vs task state files (ephemeral per-task).

### 4. Orienter Replaces repo-scout + codebase-analyzer
User challenged whether the old agents fit the new architecture. They don't:
- repo-scout: artificially constrained (1 bash call, 2 file reads) because it ran per-feature. With memory persistence, constraints are wrong -- you want thoroughness on first run.
- codebase-analyzer: produces reports for requirements-synthesizer, not knowledge for memory. Wrong format, wrong lifecycle.
- A bash script was proposed but user pointed out: "if it's known I could just fill it in on a form." Mechanical detection is busywork.
- Final answer: an LLM teammate (Orienter) that reads the project, understands patterns, writes memory. Runs once per project, not per feature.

### 5. Roles Beyond Implementation
User pushed: "we're lacking retro ceremonies. Think of it like an R&D org -- scrum masters, PMs, QA."
Research showed:
- Specialized validators (QA) outperform generalized managers in agent systems (OpenObserve case study: 380 -> 700+ tests)
- Scrum Master = hooks (already have this)
- PM = user + Synthesizer (already have this)
- EM = distributed across Validator + Reviewer + hooks
- Added: Validator teammate (acceptance testing against SPEC) and Auto-Retro subagent (automatic post-feature process learning)

## What We Tried and What Happened

### Experiment 1 Attempt 1: Orienter on caser-ts (FAILED)
**What happened:** Spawned an Agent Teams teammate using the built-in "Explore codebase" option. The Orienter explored the repo, produced a solid report, then REPORTED BACK TO THE LEAD AS A MESSAGE instead of writing to memory files.

**What we learned:**
- Agent Teams default behavior is "report to lead" -- reinforces the old context pollution pattern
- The built-in "Explore codebase" option triggers a generic exploration, not our custom protocol
- The lead couldn't resist summarizing the report into its own context
- Content quality was good -- the Orienter found real patterns, architecture, gaps
- Shutdown was awkward -- missed first shutdown request, needed retry (~3.5 min total including shutdown dance)
- CRITICAL: We need formal agent definitions (.md files), not ad-hoc prompts. The user called this out: "this is a vague testing mechanism giving us irrelevant results"

### Experiment 1 Attempt 2: Orienter on caser-ts (SUCCESS)
**What happened:** Ran `claude --agent mimir:lead --plugin-dir ~/Code/nilssonr/mimir` in caser-ts, said "Orient this project". Lead classified correctly, detected empty memory, spawned Orienter as a background teammate. Orienter explored the monorepo, wrote 5 memory files (stack.md, structure.md, conventions.md, architecture.md, domain.md) plus .orienter-state pinned to e8051c2. Team shutdown completed.

**What we learned:**
- The full pipeline works: classify -> check memory -> propose team -> spawn Orienter -> Orienter writes memory -> shutdown
- Orienter correctly wrote to memory files instead of reporting back to lead (the agent definition fixed this)
- Memory file quality was good -- accurate stack versions, patterns, architecture, domain entities
- One issue: the lead's result summary was too verbose. Printed a full table of all files and contents. User feedback: just a one-sentence confirmation for traceability is enough. Don't regurgitate what the Orienter wrote.

**Action item:** Trim the lead's post-orientation summary to a single line, e.g. "Orientation complete, 5 memory files written."

### Plugin System Discovery (pre-Experiment 1 blocker)
**What happened:** Ran `claude --plugin-dir ~/Code/nilssonr/mimir` in caser-ts. The plugin loaded but nothing took effect -- Claude behaved as default (ran git log, read files, tried to build).

**What we learned:**
- CLAUDE.md is NOT a plugin component. The plugin system auto-discovers: `agents/*.md`, `skills/*/SKILL.md`, `hooks/hooks.json`, `settings.json`. CLAUDE.md is project-level only, not recognized by the plugin loader.
- Plugin `settings.json` only supports the `agent` key. The `env` key with OTel vars was silently ignored. Unknown keys produce no warning.
- The fix: convert CLAUDE.md to `agents/lead.md` with agent frontmatter, set `settings.json` to `{"agent": "lead"}`, move env vars to `~/.claude/settings.json`.
- Use `claude --debug --plugin-dir ...` to verify plugin loading.

**What we fixed:**
- Created `agents/lead.md` (lead protocol as a default agent)
- Set plugin `settings.json` to `{"agent": "mimir:lead"}` (plugin agents are namespaced as `{plugin}:{agent}`)
- Moved OTel telemetry env vars to `~/.claude/settings.json`
- Removed `CLAUDE.md` from plugin root (no longer needed)

### Plugin Agent Namespace Discovery (pre-Experiment 1 blocker)
**What happened:** Plugin loaded (manifest fix worked), `@lead` showed in header, but Claude used default behavior -- not the lead protocol.

**What we learned:**
- Plugin agents are namespaced: `mimir:lead`, `mimir:orienter` -- not `lead`, `orienter`
- Debug log printed: `Warning: agent "lead" not found. Available agents: ..., mimir:lead, mimir:orienter. Using default behavior.`
- settings.json must use the fully-qualified name: `{"agent": "mimir:lead"}`

### Monitoring Stack Fix (pre-Experiment 1 blocker)
**What happened:** Dashboard showed no values after `docker compose up -d`.

**What we learned:**
- The `loki` exporter was removed from `otel-collector-contrib` (deprecated Sept 2024, deleted Oct 2024). The collector crashed on startup with `unknown type: "loki"`.
- Loki 3.x has native OTLP ingestion. Use `otlphttp` exporter with endpoint `http://loki:3100/otlp` (NOT `/otlp/v1/logs` -- the exporter appends `/v1/logs` automatically).
- Loki needs explicit config for OTLP: `allow_structured_metadata: true`, `tsdb` store, `v13` schema.

**What we fixed:**
- Replaced `loki` exporter with `otlp_http/loki` in otel-collector config
- Added `loki/config.yaml` with OTLP-compatible settings
- Mounted Loki config in docker-compose

### Metrics Pipeline Fix (Delta Temporality)
**What happened:** OTel collector received metrics from Claude Code and forwarded them, but Prometheus only stored `target_info`. Dashboard showed no data.

**What we learned:**
- Claude Code emits metrics with Delta aggregation temporality. Prometheus only understands Cumulative.
- The `prometheusremotewrite` exporter silently drops delta metrics.
- Fix: add `deltatocumulative` processor to the metrics pipeline before the exporter.
- Claude Code emits 6 metrics (not 3 as originally thought). The dashboard originally had 8 panels querying guessed metric names -- now all 6 real metrics are used.
- OTel attribute names use dots (`session.id`) which Prometheus converts to underscores (`session_id`).
- OTel metric units are expanded in Prometheus names: unit `s` becomes `_seconds_`, unit `count` becomes `_count_`. Always query `api/v1/label/__name__/values` to discover exact names.
- Tool execution data (tool_name, duration_ms, success) flows via OTel **logs/events** protocol to Loki, NOT via metrics to Prometheus. Querying Prometheus for tool data will always return empty.
- OTel event attributes are stored as Loki **structured metadata** (not in the JSON body). Do NOT use `| json` in LogQL queries -- attributes like `event_name`, `tool_name`, `duration_ms` are already available as labels.

**Prometheus metric names (confirmed via API):**

| OTel name | Prometheus name | Extra labels |
|---|---|---|
| `claude_code.token.usage` | `claude_code_token_usage_tokens_total` | session_id, type (input/output/cacheRead/cacheCreation), model |
| `claude_code.cost.usage` | `claude_code_cost_usage_USD_total` | session_id, model |
| `claude_code.active_time.total` | `claude_code_active_time_seconds_total` | session_id, type (user/cli) |
| `claude_code.lines_of_code.count` | `claude_code_lines_of_code_count_total` | session_id, type (added/removed) |
| `claude_code.session.count` | `claude_code_session_count_total` | session_id |
| `claude_code.code_edit_tool.decision` | `claude_code_code_edit_tool_decision_total` | session_id, tool_name, decision, source, language |

**Loki event names (via OTel logs protocol):**

| Event name | Key attributes |
|---|---|
| `claude_code.tool_result` | tool_name, duration_ms, success, session_id |
| `claude_code.api_request` | model, duration_ms, cost_usd, input_tokens, output_tokens |
| `claude_code.user_prompt` | prompt_length |
| `claude_code.api_error` | model, error, status_code |
| `claude_code.tool_decision` | tool_name, decision, source |

### Lead Architecture Pivot: Default Agent -> Opt-in Skill
**What happened:** Fixed the namespace (`mimir:lead`), plugin loaded, `@mimir:lead` showed in header. But the lead still behaved like default Claude -- reading files, running git log, trying to build. Did not follow its own protocol to spawn teammates.

**What we learned:**
- Agent Teams has a user-approval gate: "Claude won't create a team without your approval." A system prompt saying "spawn Orienter" is not the same as user approval.
- An always-on lead is the wrong model. Not all sessions need orchestration -- some are casual questions, discussions, or unrelated to code.
- The model's default behavior (answer directly) is stronger than agent system prompt instructions to delegate.
- Orientation is a dependency of certain tasks, not a session preamble. Not all code tasks start with "learn this repo."

**Architectural change:**
- Lead protocol is in `agents/lead.md`, activated via `claude --agent mimir:lead --plugin-dir ~/Code/nilssonr/mimir`.
- `settings.json` set to `{}` (no default agent). Lead is opt-in at launch time via `--agent` flag.
- The skill classifies user intent first, then checks memory freshness only when codebase knowledge is needed.
- Git-based memory freshness: `.orienter-state` written by Orienter, compared against current `git rev-parse HEAD`, branch, and dirty state.
- AskUserQuestion required for ALL questions to the user -- no freeform prose questions.

### Lead Delivery Mechanism: Skill -> --agent Flag
**What happened:** Skill approach (`/mimir:lead`) worked -- the lead classified intent, checked memory, created a team, spawned the Orienter as a proper teammate. But two issues remained:
1. The lead spawned the Orienter in the foreground (blocked the UI).
2. The lead polled for completion with sleep + ls instead of waiting for auto-delivered messages.

**What we learned:**
- `run_in_background: true` is required when spawning teammates via Task tool. Without it, the lead blocks.
- The lead must NOT poll. Teammate messages are auto-delivered. After spawning, end the turn and wait.
- The skill injection was weaker than a system prompt. Mid-session skill = injected context. `--agent` flag = system prompt from the start.

**Final form:** `claude --agent mimir:lead --plugin-dir ~/Code/nilssonr/mimir`. The `--agent` flag:
- Makes the lead protocol the system prompt (strongest instruction following)
- Sets the model via agent frontmatter (sonnet for coordination, cheaper than opus)
- Is opt-in at launch time (no orchestration tax for casual sessions)
- Alias: `alias mimir="claude --agent mimir:lead --plugin-dir ~/Code/nilssonr/mimir"`

### Agent Definition Discovery Problem
**What happened:** Lead couldn't find `agents/orienter.md` via Glob because it searched the working directory (caser-ts), not the plugin directory (mimir). The plugin's files aren't in the working directory.

**Fix:** Inlined the Orienter prompt directly in `agents/lead.md`. The lead copies it verbatim into the Task tool's `prompt` parameter. No file discovery needed. Other teammate prompts will be inlined as they're built.

### Classification Refinement
**What happened:** User said "Orient this project" but the lead still ran the full memory freshness check before spawning the Orienter. Unnecessary -- the user explicitly stated what they wanted.

**Fix:** Updated the classification table. Explicit orientation requests skip memory checks entirely and go straight to spawning the Orienter. Memory freshness checks only fire for implicit cases (feature requests, bug reports, etc.) where the lead needs to decide on its own.

### Experiment 2: Enhancer + Planner + Implementer Pipeline on caser-ts (SUCCESS)
**What happened:** Ran `claude --agent mimir:lead --plugin-dir ~/Code/nilssonr/mimir` in caser-ts, typed "add caching" (deliberately vague). Lead scored it as vague, spawned Enhancer (haiku subagent), Enhancer returned CLARIFY with 4 scoped options (gRPC, DB, HTTP headers, React Query). User pivoted to "store tokens in the db", Enhancer asked 3 follow-up questions (why, which tokens, purge strategy). User answered all three. Lead composed enhanced prompt, checked memory freshness (FRESH, 1 minor commit ahead), classified as complex, proposed Planner + Implementer(s). User approved. Planner explored codebase (7 rounds, ~3 min), wrote plan to `~/.claude/specs/nilssonr/caser-ts/refresh-token-storage.md`. Lead read plan, presented 4 dependency groups. User chose single Implementer. Implementer executed all 6 steps, 6 commits on `feat/refresh-token-storage`, 8 new tests, ~17 min. Team cleaned up.

**What worked well:**
- Enhancer correctly identified vagueness and produced project-specific clarifying questions (drew from memory)
- Planner produced a high-quality 6-step plan with accurate dependency tags, specific file:line references, actual SQL/TypeScript code, and a risk section that correctly predicted which existing tests would break
- Implementer followed the plan steps in order, committing per step (small logical commits)
- Plan cut Implementer exploration from ~7 rounds (Planner) to ~3 rounds -- meaningful savings
- Memory freshness check correctly assessed FRESH with minor drift
- Full pipeline: vague prompt -> clarified -> enhanced -> classified -> planned -> implemented -> committed in ~21 min

**Issues found:**
1. **Lead violated confirmation output rule.** Printed a full 6-row table with commit hashes after implementation. Should have been one sentence. The rule added before this experiment wasn't strong enough to override the model's instinct to summarize.
2. **Planner lifecycle gap.** Planner was not shut down before spawning Implementer. Stayed alive as idle teammate throughout implementation (~17 min of wasted context).
3. **Lead skipped second Enhancer call.** After CLARIFY answers came back, the lead composed the enhanced prompt itself instead of re-running the Enhancer with the answers. Worked fine but deviated from the protocol ("Re-run Step 0 with the user's answers").
4. **Implementer re-read files.** ~3 rounds of reading vs Planner's ~7. Plan halved exploration but didn't eliminate it. Implementer needs current file content to make edits -- plan references alone aren't enough.
5. **Lint appeared to timeout.** `pnpm -w lint` showed a timeout indicator during Implementer execution, but manual run completes in ~7.5s. Likely a stacked command or output buffering issue, not a real timeout.

**Metrics:**
- Enhancement: ~4s (haiku subagent, 2 rounds: CLARIFY then composed by lead)
- Planning: ~3 min (sonnet teammate, 7 rounds of file reading, 217-line plan)
- Implementation: ~17 min (sonnet teammate, 6 steps, lint/format iterations)
- Total: ~21 min for migration + repository + service + wiring + 8 tests

**Action items:**
- Strengthen confirmation output rule in lead.md (table violation despite explicit rule)
- Add Planner shutdown step before Implementer spawn in lead protocol
- Clarify Enhancer re-run protocol (should lead re-run Enhancer or compose itself after CLARIFY?)
- Investigate lint timeout indicator (lint runs in ~7.5s manually, but showed timeout during Implementer execution)

## What's Confirmed (high confidence)

1. The role decomposition is sound -- 6 teammates, 4 subagents, clear boundaries
2. Memory-first architecture is the right model -- eliminates re-discovery
3. Lead via `--agent` flag is the right delivery mechanism (opt-in, system prompt strength)
4. File-based state over conversation state -- proven by SPEC pattern
5. Plugin distribution is the right delivery mechanism -- replaces Makefile symlinks
6. OpenTelemetry telemetry works -- metrics flow through deltatocumulative -> Prometheus
7. Git hash comparison is the right freshness signal for memory
8. Enhancer improves prompt quality -- CLARIFY mode correctly identified ambiguity, produced project-specific questions from memory (Experiment 2)
9. Planner produces actionable plans -- 6 steps, accurate dependency tags, specific file:line references, risk section that predicted test breakage (Experiment 2)
10. Full pipeline works end-to-end -- Enhance -> Classify -> Check Memory -> Plan -> Implement -> Commit (Experiment 2)

## What's Unconfirmed (needs experiments)

1. ~~**Lead skill triggers team creation (0.60)**~~ -- CONFIRMED (Experiment 1). Lead classifies, checks memory, spawns Orienter via Agent Teams.
2. **Memory enrichment by teammates (0.35)** -- will teammates reliably write back convention discoveries? Implementer in Experiment 2 did NOT enrich memory. Relies on Auto-Retro (not built) and Orienter (next session).
3. ~~**Plan precision enabling parallelization (0.40)**~~ -- CONFIRMED (Experiment 2). Planner produced 6 steps with accurate dependency tags (4 groups). Plan halved Implementer exploration time. File:line references were correct. Risk section predicted test breakage.
4. ~~**Ephemeral teammate cost (0.45)**~~ -- PARTIALLY CONFIRMED (Experiment 2). Planning ~3 min + implementation ~17 min = ~21 min total for a real feature. Acceptable but Planner lifecycle gap (not shut down before Implementer) wasted context.
5. ~~**Orienter memory quality (0.50)**~~ -- CONFIRMED (Experiment 1). Accurate stack, patterns, architecture, domain. 5 files + .orienter-state.
6. **Validator value-add (0.50)** -- does it catch gaps that TDD + Review miss?
7. ~~**Agent Teams stability (0.40)**~~ -- PARTIALLY CONFIRMED (Experiments 1+2). Full pipeline worked end-to-end. Known issues: shutdown dance (Exp 1), Planner not shut down before Implementer spawn (Exp 2). No crashes or data loss.

## What's Built

```
~/Code/nilssonr/mimir/
  .claude-plugin/plugin.json     -- v0.1.0 plugin manifest
  DESIGN.md                      -- full architecture spec
  HANDOFF.md                     -- this file
  settings.json                  -- {} (no default agent; lead is opt-in via --agent flag)
  .gitignore
  agents/
    lead.md                      -- lead coordinator (activated via --agent mimir:lead)
    orienter.md                  -- project exploration teammate, writes .orienter-state
    enhancer.md                  -- inline subagent for vague prompt refinement (haiku)
    planner.md                   -- teammate for implementation plans with dependency tags (sonnet)
    implementer.md               -- teammate for code changes, TDD cycle, commits (sonnet)
  hooks/
    scripts/                     (empty -- hook scripts not yet written)
  monitoring/
    docker-compose.yml           -- OTel Collector + Prometheus + Loki + Grafana
    otel-collector/config.yaml   -- deltatocumulative + otlp_http/loki
    loki/config.yaml             -- OTLP-compatible config (tsdb, v13 schema)
    prometheus.yml
    grafana/                     -- dashboard with real Claude Code metric names
```

OTel telemetry env vars live in `~/.claude/settings.json` (global), not the plugin.

### Enhancer + Planner Design (post-Experiment 1)

**Problem:** The gap between classification and implementation caused two issues:
1. Vague prompts get misclassified (no enhancement step)
2. Without a plan, the lead can't determine whether to parallelize Implementers

**Solution:** Two new agents fill the gap:
- **Enhancer** (subagent, haiku): Refines vague prompts before classification. Triggered by cumulative heuristic scoring (word count, lazy phrases, missing file refs, missing scope words, missing acceptance criteria). Score >= 1.5 triggers enhancement. Lead presents both versions to user via AskUserQuestion.
- **Planner** (teammate, sonnet): Explores codebase and writes plan files with dependency tags to specs directory. Lead reads the plan's parallelization section to spawn Implementers in parallel groups.

**Key decisions:**
- Enhancer is a subagent (not teammate) because prompt enhancement is fast, single-shot, and needs no codebase access
- Planner is a teammate (not subagent) because plan quality requires codebase exploration
- Enhancement runs BEFORE classification (Step 0) because vague prompts cause misclassification
- Simple tasks skip the Planner entirely -- direct to single Implementer

**Updated lifecycle:** ENHANCE -> CLASSIFY -> CHECK MEM -> PLAN -> EXECUTE -> VALIDATE -> INTEGRATE -> AUTO-RETRO

### Lead Tool Restrictions + Implementer (post-Experiment 1 field test)

**Problem:** The lead explored the codebase directly (using Explore subagent, Read on source files) instead of delegating to a teammate. Root cause: the lead had access to all tools and no Implementer prompt to delegate to, so it "just did the work" -- especially with `--allow-dangerously-skip-permissions`.

**Solution:**
1. **Tool restrictions in lead.md** -- explicit allowed/forbidden tool lists. Bash only for 3 git commands. Read only for memory/plan files. No Glob, Grep, Edit, Write, Explore, WebFetch, WebSearch.
2. **Blocked fallback** -- if a role is needed but undefined, the lead outputs `[BLOCKED] Need {role} teammate but agents/{role}.md is not defined yet. Wanted to: {description}.` and stops.
3. **Implementer agent** -- receives task context (direct or from plan step), explores code, implements, tests, commits, reports back with commit hash.

**Key insight:** Prompt-level tool restrictions are the only mechanism available (agent frontmatter doesn't support tool restrictions). The constraints must be strong enough to override the model's bias toward direct action when all tools are technically available.

## What's Not Built

- agents/validator.md, reviewer.md, investigator.md, researcher.md
- hooks/hooks.json and hook scripts
- No git commits yet (repo is initialized but uncommitted)

## Environment State

- claude-skills: fully unlinked from ~/.claude/ (make unlink ran successfully)
- ~/.claude/settings.json: has Agent Teams enabled + plugins + no hooks
- ~/.claude/CLAUDE.md: restored from backup (pre-claude-skills version)
- caser-ts project: existing MEMORY.md at ~/.claude/projects/-Users-ingemar-Code-nilssonr-caser-ts/memory/MEMORY.md (62 lines, good baseline for Orienter comparison)

## Next Steps (in order)

1. ~~Monitoring stack is running~~ DONE
2. ~~Run Experiment 1~~ DONE (SUCCESS -- Attempt 2)
3. ~~Trim lead's post-orientation output to one-sentence summary~~ DONE (committed 8e72fc9)
4. ~~Write Enhancer + Planner + Implementer agent definitions~~ DONE
5. ~~Run Experiment 2: Enhancer + Planner + Implementer pipeline~~ DONE (SUCCESS)
6. ~~Fix Experiment 2 issues: strengthen confirmation output rule, add Planner shutdown step, clarify Enhancer re-run protocol~~ DONE (committed f9447b3)
7. Write remaining agent definitions (validator, reviewer, investigator, researcher)
8. Write Auto-Retro subagent (needed for decisions.md enrichment)
9. Write hooks
10. Run Experiment 3: parallel Implementers in worktrees

## How to Resume

```bash
cd ~/Code/nilssonr/mimir
claude
# Then say: "Read HANDOFF.md and DESIGN.md. Resume from Next Steps."
```

Or from any repo:
```bash
claude
# Then say: "Read ~/Code/nilssonr/mimir/HANDOFF.md and resume the mimir project."
```
