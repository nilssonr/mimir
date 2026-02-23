#!/usr/bin/env bash
# hooks/scripts/commit-validator.sh
# Validates conventional commit format before git commit executes.
set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only intercept git commit commands
if [[ ! "$command" == *"git commit"* ]] || [[ ! "$command" == *"-m"* ]]; then
  exit 0
fi

# Extract commit message
# Try heredoc-style first: -m "$(cat <<'EOF'\nmessage\nEOF\n)"
msg=$(echo "$command" | awk '/cat <</{found=1; next} /^[[:space:]]*EOF/{found=0} found{print; exit}' | sed 's/^[[:space:]]*//')

# Fall back to simple -m "message" or -m 'message'
if [ -z "$msg" ]; then
  msg=$(echo "$command" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
if [ -z "$msg" ]; then
  msg=$(echo "$command" | sed -n "s/.*-m[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
fi

if [ -z "$msg" ]; then
  exit 0
fi

# Validate conventional commit format
if [[ ! "$msg" =~ ^(feat|fix|docs|style|refactor|perf|test|chore)(\(.+\))?\!?:\ .+ ]]; then
  echo "Commit message must follow conventional commits: type(scope): description" >&2
  echo "Types: feat, fix, docs, style, refactor, perf, test, chore" >&2
  echo "Got: $msg" >&2
  exit 2
fi

exit 0
