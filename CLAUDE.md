# Mimir

A Claude Code plugin that orchestrates software engineering work through a pipeline of specialized agents, named after figures from Norse mythology.

## How it works

**Odin** is the entry point. He classifies intent, recommends approaches, dispatches agents, and tracks pipeline state. He never writes code. All agents are defined as Claude Code subagents with frontmatter specifying model, tools, and description.

Pipeline: Huginn (orient) → Frigg (plan) → Thor (implement) → Heimdall (validate) → Forseti (review) → Saga (retro)

## Directory map

```
agents/     — agent definitions (odin, frigg, thor, heimdall, forseti, saga, mimir, ...)
skills/     — reusable instruction sets injected into agent prompts at dispatch time
hooks/      — hook scripts and hooks.json (commit-validator, auto-format, stop-gate, session-start)
settings.json — plugin entry point: {"agent": "odin"}
```

## Working on Mimir

Use the Mimir agent — it reads accumulated project memory and has opinions:

```bash
claude --agent mimir:mimir --plugin-dir /path/to/mimir
```

Accumulated knowledge (research findings, architectural decisions, past run issues) lives in project memory at `~/.claude/projects/*/memory/`. Mimir reads it at Bootstrap. Don't duplicate it here.

## Architectural principle

Sparse spec. Less prescription produces better model behavior. v1 had a 46KB conductor that violated its own rules 3/3 experiments. v2 Odin is ~450 lines. When in doubt, don't add rules — add to `issues.md` and learn from runs.
