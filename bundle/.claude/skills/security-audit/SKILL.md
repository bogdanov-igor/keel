---
name: security-audit
description: Targeted security review of a file set or diff — secrets exposure, injection vectors, auth gaps, XSS, CORS — with graded findings filed into BACKLOG.md.
---

# security-audit

Scoped application-security pass over a directory, single file, or git diff ref.
Supply-chain CVEs (npm audit / pip-audit / govulncheck) are a separate concern —
this skill covers application code only.

Before starting: if BACKLOG.md already has 20+ open findings, burn down first
instead of auditing (same WIP rule as skill audit).

## Checks

Run all five unless the request narrows scope. Save raw grep output under
`.qa/security/` so every finding has an evidence path; read back only the
match counts and the lines you need.

1. **Secrets exposure.**
   ```bash
   grep -rn -E \
     "(password|secret|api_key|token|private_key|bearer)\s*[:=]\s*['\"][^'\"]{8,}" \
     "$TARGET" --include="*.ts" --include="*.js" --include="*.py" \
     | grep -v "process\.env\|os\.environ\|{{secret:" > .qa/security/secrets.txt
   ```

2. **Injection vectors.**
   ```bash
   # SQL injection: raw string interpolation in queries
   grep -rn -E "\`SELECT|\.query\(\`|\.raw\(\`|execute\(\`" \
     "$TARGET" 2>/dev/null > .qa/security/injection.txt
   # Command injection
   grep -rn -E "exec\(|spawn\(|shell\.exec" \
     "$TARGET" 2>/dev/null >> .qa/security/injection.txt
   ```

3. **Auth guard check** — API routes without a session/token check.
   ```bash
   find "$TARGET" -name "route.ts" -o -name "*.handler.ts" | \
     while read -r f; do
       grep -qE "getSession|getUser|verifyToken|authenticate" "$f" || \
         grep -qE "@public|// public" "$f" || echo "NO_AUTH: $f"
     done > .qa/security/noauth.txt
   ```

4. **XSS vectors.**
   ```bash
   grep -rn -E "dangerouslySetInnerHTML|\.innerHTML\s*=|document\.write" \
     "$TARGET" --include="*.tsx" --include="*.jsx" > .qa/security/xss.txt
   ```

5. **CORS misconfiguration.**
   ```bash
   grep -rn -E "Access-Control-Allow-Origin.*\*|cors\(\)" \
     "$TARGET" 2>/dev/null > .qa/security/cors.txt
   ```

## Grading

- **P0** — hardcoded secret in source, SQL injection via string interpolation,
  unauthenticated route touching sensitive data.
- **P1** — XSS vector reachable from user input, CORS wildcard on a
  non-public endpoint.
- **P2** — sensitive fields in logs, default `cors()` on an internal service,
  auth check present but bypassable.
- **P3** — hardening suggestions with no demonstrated exposure.

## Filing findings

Each finding becomes one BACKLOG.md line:

```text
- [ ] P0 | src/lib/client.ts:14 | Hardcoded API token; move to .secrets.env and reference {{secret:API_TOKEN}} or process.env | ev:.qa/security/secrets.txt | src:security-audit
```

Keep the remediation hint inside the one-liner when it fits; longer context
stays in the evidence file. Fixing findings that span several surfaces or
risky refactors goes through skill stage, not ad-hoc edits.

Close the pass with a verdict: clean means zero P0 and zero P1. Always state
what was not covered (checks skipped, paths excluded).

If the target is binary, minified, or obfuscated, the grep patterns are
unreliable — file one P2 line flagging the path for manual review instead of
reporting a false clean.

## Gotchas

- `process.env.*`, `os.environ`, and `{{secret:*}}` references are the
  correct pattern — never report them as secret exposure.
- Don't flag XSS in server-rendered contexts where the value is provably
  server-controlled.
- Don't suppress matches: every grep hit gets a finding line, even when
  context suggests it is safe — mark low confidence in the one-liner and let
  the reviewer decide.
- A recurring vulnerability pattern specific to this codebase is worth a note
  via skill remember; one-off findings are not.
