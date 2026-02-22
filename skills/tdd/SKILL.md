---
name: tdd
description: Write-only test-driven development. Write tests first, then implement. Never run tests — the Validator handles all verification.
---

# Write-Only TDD

Write tests FIRST, then implement to satisfy them conceptually. NEVER run tests. The Validator runs all verification.

## Cycle

1. **RED**: Write tests that define the expected behavior. Each test covers one acceptance criterion.
2. **GREEN**: Write the minimum implementation to make tests pass conceptually.
3. **REFACTOR**: Clean up without changing behavior. Only refactor code you wrote.
4. **COMMIT**: Commit test + implementation together using git-workflow conventions.

## RED Phase

- Read acceptance criteria from the spec
- Match existing test patterns (framework, style, naming, directory structure) from the project
- Each test exercises NEW behavior that doesn't exist yet
- Tests should be specific — one assertion per concept
- Name tests descriptively: what behavior, under what conditions, expected outcome
- Do NOT run the tests

## GREEN Phase

- Read the tests to understand expectations
- Find where implementation should live (adjacent to tests, matching project structure)
- Read nearby files to match existing patterns (imports, naming, error handling)
- Write the MINIMUM code to make tests pass conceptually
- Do NOT add features beyond what tests require
- Do NOT run the tests

## REFACTOR Phase

- Review for: duplication, complexity, naming, missing error context
- If clean: skip. "No refactoring needed" is valid and encouraged.
- Only refactor code you wrote — not surrounding code
- Do NOT run the tests

## When to Skip TDD

Not every task needs RED-GREEN-REFACTOR:
- Config changes, typo fixes, dependency updates → just make the change
- Refactoring with existing test coverage → make changes, trust existing tests
- Plan step says "no new tests needed" → trust the Planner

When in doubt, write tests.

## Rules

- **NEVER run tests.** Not once. Not to check. Not to verify. The Validator does that.
- The test file is the contract. Tests capture the requirement.
- Do NOT modify tests after writing them in the RED phase.
- Each TDD cycle produces one commit (test + implementation together).
- Writing good tests is more important than writing clever implementation.
