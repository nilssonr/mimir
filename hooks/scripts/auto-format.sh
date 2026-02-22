#!/usr/bin/env bash
# hooks/scripts/auto-format.sh
# Auto-formats files after Write/Edit operations.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [ -z "$file_path" ]; then
  exit 0
fi

# Resolve relative to project dir
full_path="${CLAUDE_PROJECT_DIR:-$(pwd)}/$file_path"

if [ ! -f "$full_path" ]; then
  exit 0
fi

case "$file_path" in
  *.go)       gofmt -w "$full_path" 2>/dev/null ;;
  *.rs)       rustfmt "$full_path" 2>/dev/null ;;
  *.ts|*.tsx|*.js|*.jsx) npx prettier --write "$full_path" 2>/dev/null ;;
  *.cs)       dotnet format "$full_path" 2>/dev/null ;;
  *.py)       ruff format "$full_path" 2>/dev/null ;;
esac

exit 0
