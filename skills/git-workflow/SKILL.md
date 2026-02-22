---
name: git-workflow
description: Git conventions for branching, commits, and workflow. Enforced by commit-validator hook.
---

# Git Workflow

## Branching

- On main/master → create `type/description` branch (e.g., `feat/add-oauth`, `fix/logout-redirect`).
- Already on feature branch → continue. Don't create nested branches.
- NEVER commit to main/master directly.

## Commits

Commit after each logical step. Never batch a whole plan into one commit.

### Format

```
type(scope): description
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
Breaking changes: `feat(auth)!: remove password login`

### HEREDOC (always use for commit messages)

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add OAuth2 PKCE flow

Implements authorization code flow with PKCE for public clients.
EOF
)"
```

### Guidelines

- Small, logical commits > big batched ones
- Separate test commits from implementation when they're distinct steps:
  - `test(auth): add tests for PKCE flow`
  - `feat(auth): implement PKCE flow`
- Or combine when the change is atomic: `fix(auth): handle expired tokens`

## Pushing

- After rebase: `git push --force-with-lease` (NEVER `--force`)
- If rejected: someone else pushed. Fetch and re-examine.

## Rules

- Rebase over merge.
- Check `git status` before committing.
- After any code change is complete: commit immediately. Uncommitted work is unfinished work.
- The commit-validator hook enforces conventional commit format. Don't fight it.
- The auto-format hook runs on saves. Don't manually format.
