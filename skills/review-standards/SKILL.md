---
name: review-standards
description: 11-dimension code review checklist with confidence scoring. Used by Validator and Reviewer agents.
---

# Review Standards

## Confidence Scoring

Every finding gets a confidence score (0-100). Suppress findings below 80.

| Score | Meaning |
|---|---|
| 90-100 | Certain. Verified with evidence (file:line, test output). |
| 80-89 | High confidence. Strong signals, minor uncertainty. |
| 70-79 | Moderate. Suppressed — note only if user explicitly asks. |
| 0-69 | Low. Do not report. |

## Severity Levels

**[CRIT]** — Bugs, security vulnerabilities, data loss risk, race conditions, broken error handling on critical paths, breaking API changes without versioning. Must fix before merge.

**[WARN]** — Design concerns, performance issues, missing tests on critical paths, CQS violations, excessive complexity, hidden side effects. Should address before or shortly after merge.

**[INFO]** — Naming improvements, documentation gaps, minor simplification opportunities. Take or leave.

### Calibration

1. A typo in a log message is not [CRIT]. An SQL injection is not [INFO].
2. Downgrade one level when confidence is below 90.
3. Unverified cross-codebase findings cap at [WARN].
4. Two dimensions on same finding → use higher severity, note both.
5. Style (formatting, whitespace, import order) is NEVER a finding. That belongs to linters.

## 11 Dimensions

Work through every applicable dimension. Skip dimensions that don't apply to the diff/code under review.

### 1. Correctness
Off-by-one errors, null/nil/undefined handling, boundary conditions (empty collections, zero-length, max/min), logic errors (wrong boolean operators, precedence), race conditions, deadlocks, resource leaks (unclosed handles, missing defer/finally), integer overflow, unchecked return values, unhandled error paths.

### 2. Security
Injection (SQL, OS command, XSS), auth/authz bypass, IDOR without ownership check, secrets in code, deprecated crypto (MD5, SHA1, DES), unsafe deserialization, path traversal, SSRF, missing CSRF, sensitive data in logs. Map to CWE when applicable.

### 3. Error Handling
Swallowed errors (empty catch), missing error context on re-throw, overly broad catches (base Exception), panic on expected conditions, retry without backoff, infrastructure errors leaking to users.

### 4. Performance
N+1 queries (DB/API call in loop), hidden O(n²) (.find/.filter inside loop), unbounded allocations (SELECT without LIMIT), sync blocking in async context, missing caching for repeated computation, string concatenation in tight loops.

### 5. Defensiveness
Input validation at trust boundaries (type, range, length, format), allowlist over denylist, preconditions at function entry, matched resource pairs (open/close, lock/unlock), timeouts on external calls, immutability for thread safety.

### 6. Readability
Cyclomatic complexity: ≤10 OK, 11-15 INFO, 16-20 WARN, >20 CRIT. Function length: ≤40 OK, 41-60 INFO, 61-100 WARN, >100 CRIT. Nesting depth: ≤3 OK, 4 WARN, >4 CRIT. Names describe actions (functions), content (variables), predicates (booleans).

### 7. Cognitive Load
Parameter lists: 4-6 WARN, 7+ CRIT. Boolean flag parameters (split into named functions). Mixed abstraction levels in same function. Implicit state machines (multiple booleans → use enum). Temporal coupling (init must precede use without enforcement).

### 8. Testability
Constructor does real work (I/O, complex logic), Law of Demeter violations, global state/singletons, SRP violations, critical paths untested, tests verify implementation details instead of behavior.

### 9. Consistency
Within-diff: uniform naming, error handling, abstraction levels. Cross-codebase: new code matches established patterns. Verify with Grep before flagging — don't fabricate patterns. Naming synonyms (getUser vs fetchUser in same layer).

### 10. Side Effects & Purity
CQS violations: getters that mutate state. Hidden side effects: mutation of input arguments, global state writes, I/O in pure-looking functions. Names that hide side effects (validateEmail that also sends email).

### 11. API Design
Backward compatibility (removed fields, changed types = breaking if unversioned). Idempotency for PUT/retry. Naming consistent with existing API surface. Structured error responses. Minimize observable surface area.

## Review Priority

Spend analysis time proportionally:
1. Correctness, Security (highest — causes incidents)
2. Error Handling, Side Effects (high — silent failures)
3. Performance, Defensiveness (medium — operational risk)
4. Cognitive Load, Readability (medium — maintenance)
5. Testability, API Design (context-dependent)
6. Consistency (lowest — important but rarely critical)

## Finding Format

```
[SEVERITY] file:line — dimension: description (Confidence: N/100)
  → suggested fix (concrete and specific)
```

## Report Structure

```
# Review/Validation: {scope}

## Summary
{one sentence: N findings, severity breakdown, confidence range}

## Findings
{ordered by severity: CRIT first, then WARN, then INFO}
{each with file:line, dimension, description, confidence, fix}

## Strengths
{2-3 things done well}

VERDICT: PASS | CONCERNS | FAIL
```

| Verdict | Condition |
|---|---|
| PASS | Zero critical, ≤ 2 warnings |
| CONCERNS | Zero critical, > 2 warnings |
| FAIL | Any critical finding |

## Rules

1. Every finding: file, line, dimension, description, confidence score, concrete fix.
2. Stay in scope. Don't request changes outside the diff.
3. Style is not a finding. Formatting belongs to linters.
4. Max 30 findings. Keep highest severity if more.
5. A clean PASS is valid. Don't manufacture findings to appear thorough.
6. Do not fabricate patterns. If you can't verify a cross-codebase pattern, say so.
