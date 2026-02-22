# Mimir

A Claude Code plugin that orchestrates software engineering work through a pipeline of specialized agents.

## How it works

The **conductor** is the entry point. It classifies intent, recommends approaches, dispatches agents, and tracks pipeline state. It never writes code. All agents are defined as Claude Code subagents with frontmatter specifying model, tools, and description.

Pipeline: orient → plan → implement → validate → review → retro

## Directory map

```
agents/     — agent definitions (conductor, planner, implementer, validator, reviewer, retro, ...)
skills/     — reusable instruction sets injected into agent prompts at dispatch time
hooks/      — hook scripts and hooks.json (commit-validator, auto-format, stop-gate, session-start)
settings.json — plugin entry point: {"agent": "conductor"}
```

## Working on Mimir

Use the meta agent — it reads accumulated project memory and has opinions:

```bash
claude --agent mimir:meta --plugin-dir /path/to/mimir
```

Accumulated knowledge (research findings, architectural decisions, past run issues) lives in project memory at `~/.claude/projects/*/memory/`. Meta reads it at Bootstrap. Don't duplicate it here.

## Architectural principle

Sparse spec. Less prescription produces better model behavior. v1 had a 46KB conductor that violated its own rules 3/3 experiments. v2 conductor is ~450 lines. When in doubt, don't add rules — add to `issues.md` and learn from runs.
