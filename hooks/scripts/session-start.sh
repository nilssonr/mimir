#!/usr/bin/env bash
# hooks/scripts/session-start.sh
# Injects project context on session start, resume, clear, and compact.
set -euo pipefail

cat /dev/stdin > /dev/null  # consume stdin

# Project context
BRANCH=$(git branch --show-current 2>/dev/null || echo "no-git")
COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits")
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
STACK=""
[ -f go.mod ] && STACK="$STACK Go"
[ -f Cargo.toml ] && STACK="$STACK Rust"
[ -f angular.json ] && STACK="$STACK Angular"
[ -f package.json ] && STACK="$STACK Node/TS"
[ -n "$(ls *.csproj 2>/dev/null)" ] && STACK="$STACK C#"
[ -f pyproject.toml ] && STACK="$STACK Python"
STACK=$(echo "$STACK" | xargs)  # trim

# Check pipeline state
PIPELINE=""
if [ -f ~/.claude/state/mimir/pipeline.yaml ]; then
  STAGE=$(grep '^stage:' ~/.claude/state/mimir/pipeline.yaml 2>/dev/null | awk '{print $2}')
  TASK_ID=$(grep '^task_id:' ~/.claude/state/mimir/pipeline.yaml 2>/dev/null | awk '{print $2}')
  if [ -n "$STAGE" ] && [ "$STAGE" != "complete" ]; then
    PIPELINE="Pipeline in progress: $TASK_ID (stage: $STAGE)"
  fi
fi

cat <<EOF
<project-context>
Branch: $BRANCH | Last commit: $COMMIT | Uncommitted files: $DIRTY
Stack: ${STACK:-unknown}
${PIPELINE:+$PIPELINE}
</project-context>
EOF
