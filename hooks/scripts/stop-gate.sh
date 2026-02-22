#!/usr/bin/env bash
# hooks/scripts/stop-gate.sh
# Blocks completion if tests fail or code changes are uncommitted.
set -euo pipefail

input=$(cat)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')

# Prevent infinite loop
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

# Check for modified code files (staged or unstaged)
changed=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only --cached 2>/dev/null || echo '')
code_changed=$(echo "$changed" | grep -E '\.(go|rs|ts|tsx|cs|js|jsx|py)$' || true)

if [ -z "$code_changed" ]; then
  exit 0
fi

# Run tests for detected stack
if [ -f 'go.mod' ]; then
  go test ./... 2>&1 | tail -5 || { echo "Go tests failing. Fix before completing." >&2; exit 2; }
fi
if [ -f 'Cargo.toml' ]; then
  cargo test 2>&1 | tail -10 || { echo "Rust tests failing. Fix before completing." >&2; exit 2; }
fi
if [ -f 'package.json' ] && grep -q '"test"' package.json 2>/dev/null; then
  # Detect package manager
  if [ -f 'bun.lockb' ]; then
    bun test 2>&1 | tail -10 || { echo "Tests failing. Fix before completing." >&2; exit 2; }
  elif [ -f 'yarn.lock' ]; then
    yarn test 2>&1 | tail -10 || { echo "Tests failing. Fix before completing." >&2; exit 2; }
  elif [ -f 'pnpm-lock.yaml' ]; then
    pnpm test 2>&1 | tail -10 || { echo "Tests failing. Fix before completing." >&2; exit 2; }
  else
    npm test -- --passWithNoTests 2>&1 | tail -10 || { echo "Tests failing. Fix before completing." >&2; exit 2; }
  fi
fi
if ls *.csproj 1>/dev/null 2>&1; then
  dotnet test 2>&1 | tail -10 || { echo ".NET tests failing. Fix before completing." >&2; exit 2; }
fi

# Check for uncommitted code changes
uncommitted=$(git status --porcelain 2>/dev/null | grep -E '\.(go|rs|ts|tsx|cs|js|jsx|py)$' || true)
if [ -n "$uncommitted" ]; then
  echo "Tests pass but changes are uncommitted. Commit using git-workflow conventions before finishing." >&2
  exit 2
fi

exit 0
