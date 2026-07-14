---
name: test-authoring
description: Author unit and integration tests for a target file or function — happy path, edge cases, error states — and estimate the coverage delta. Use when code lacks tests or a change needs regression protection.
---

# test-authoring

Input: a target file or function to test. Optional: test kinds (default unit;
add integration when real DB/network paths matter) and a coverage target
(default 0.8 branch coverage ratio).

## Steps

1. **Detect the test framework** (skip if already known):
   ```bash
   grep -E '"vitest"|"jest"|"mocha"' package.json | head -1
   # Python: look for pytest.ini or pyproject.toml; Go: go test
   ```

2. **Analyse the target file.** Read it and extract:
   - Exported functions/classes and their signatures.
   - Branch points (if/switch/ternary/try-catch).
   - External dependencies (imports) — decide which to mock.
   - Existing test file (`<target>.test.<ext>` or `__tests__/<target>.<ext>`) —
     append to it rather than duplicating.

3. **Identify test cases.** For each exported function:
   - Happy path: valid inputs, expected output.
   - Edge cases: empty input, boundary values, null/undefined.
   - Error states: thrown errors, rejected promises, validation failures.
   - Integration paths (only if requested): real DB/network interactions.

4. **Write the test file** (`<target>.test.<ext>`):
   - Import the function under test; mock external dependencies
     (`vi.mock` / `jest.mock` / `unittest.mock`).
   - One `describe` block per function, one `it`/`test` per case.
   - Each test: arrange → act → assert. No shared mutable state between tests.

5. **Estimate the coverage delta** (rough heuristic):
   ```bash
   branches=$(grep -cE "\bif\b|\bswitch\b|\b\?\s" "$target_file" || echo 0)
   cases=$(grep -cE "\bit\(|\btest\(|def test_" "$test_file" || echo 0)
   # delta ≈ cases / (branches * 2)
   ```

6. **Run the suite** to confirm the new tests are green before reporting done.

## Done / not done

- Done: test file written, at least one test per exported function, estimated
  coverage delta of at least half the coverage target (half is acceptable for
  initial authoring), suite green.
- Not done: no test file, or zero cases for one or more exported functions.
- Blocked: the target has external dependencies that cannot be reliably mocked
  (DB state, third-party API without a sandbox). Stop and queue it instead of
  writing brittle mocks:
  `- [ ] P2 | tests | <target> needs manual integration-test design (unmockable deps) | ev:<target path> | src:test-authoring`

## Reporting

- Summarize in chat: cases authored by kind (happy path / edge / error),
  mocks used, estimated coverage delta, suite result.
- Remaining gaps (untested exports, skipped integration paths) go into
  BACKLOG.md as `- [ ] P0..P3 | tests | <one line> | ev:<path> | src:test-authoring`.
- Testing across many files or a whole module is multi-unit work — run it
  via skill stage. A non-obvious mocking or framework gotcha discovered along
  the way → record via skill remember.

## Anti-patterns

- Tests that share mutable state; each test must be independent.
- Mocking the module under test — only mock its dependencies.
- Snapshot tests for business logic; use explicit assertions.
- Skipping error-state tests; they are the most valuable for regression protection.
- Chasing 100% coverage at the cost of test quality; meaningful assertions
  beat line coverage.
