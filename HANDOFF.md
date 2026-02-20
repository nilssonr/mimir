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
- Claude Code emits 3 metrics: `claude_code.cost.usage` (USD), `claude_code.token.usage` (tokens), `claude_code.active_time.total`. The dashboard originally had 8 panels querying guessed metric names -- 5 of those metrics don't exist.
- Rebuilt dashboard with only the 3 real metrics.
- OTel attribute names use dots (`session.id`) which Prometheus converts to underscores (`session_id`).

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

## What's Confirmed (high confidence)

1. The role decomposition is sound -- 6 teammates, 4 subagents, clear boundaries
2. Memory-first architecture is the right model -- eliminates re-discovery
3. Lead via `--agent` flag is the right delivery mechanism (opt-in, system prompt strength)
4. File-based state over conversation state -- proven by SPEC pattern
5. Plugin distribution is the right delivery mechanism -- replaces Makefile symlinks
6. OpenTelemetry telemetry works -- metrics flow through deltatocumulative -> Prometheus
7. Git hash comparison is the right freshness signal for memory

## What's Unconfirmed (needs experiments)

1. ~~**Lead skill triggers team creation (0.60)**~~ -- CONFIRMED (Experiment 1). Lead classifies, checks memory, spawns Orienter via Agent Teams.
2. **Memory enrichment by teammates (0.35)** -- will teammates reliably write back convention discoveries?
3. **Plan precision enabling parallelization (0.40)** -- can the Planner decompose into truly independent modules with accurate dependency tags?
4. **Ephemeral teammate cost (0.45)** -- is teammate spawn overhead acceptable for single-task usage?
5. ~~**Orienter memory quality (0.50)**~~ -- CONFIRMED (Experiment 1). Accurate stack, patterns, architecture, domain. 5 files + .orienter-state.
6. **Validator value-add (0.50)** -- does it catch gaps that TDD + Review miss?
7. **Agent Teams stability (0.40)** -- experimental feature with known limitations

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
3. Trim lead's post-orientation output to one-sentence summary (user feedback from Experiment 1)
4. ~~Write Enhancer + Planner + Implementer agent definitions~~ DONE
5. Write remaining agent definitions (validator, reviewer, investigator, researcher)
6. Write hooks
7. Initial git commit
8. Run Experiment 2: test Enhancer + Planner pipeline end-to-end

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
