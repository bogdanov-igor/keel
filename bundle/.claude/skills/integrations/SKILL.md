---
name: integrations
description: Inventory what this project can actually reach — CLIs, Playwright browsers, MCP servers, secrets, Claude Design, second-opinion models — by detecting what exists, asking the owner about each, and recording the answers in OPS.md, PARKED.md, and BACKLOG.md. Run on the first session after installing Keel, or when the owner asks what this project can reach.
disable-model-invocation: true
argument-hint: "[all | <tool>]"
---

# Integrations

Access is the owner's to grant, never yours to acquire. This skill
turns "what can this project reach?" from a per-session guess into
lines in `OPS.md` that every later session reads.

Three rules, no exceptions: **never install anything, never sign in
anywhere, never write a credential into any file.** Detect, ask,
record. An argument (`<tool>`) narrows the pass to one item.

## 1. Detect what is on the machine

```sh
for c in gh uvx npx node python3 codex gemini; do
  printf '%-8s %s\n' "$c" "$(command -v -- "$c" || echo 'absent')"
done
ls ~/Library/Caches/ms-playwright ~/.cache/ms-playwright 2>/dev/null   # browsers
[ -f .mcp.json ] && python3 -c 'import json;print(*json.load(open(".mcp.json")).get("mcpServers",{}))'  # MCP servers
[ -f .secrets.env ] && echo '.secrets.env present'                     # names only
```

Presence is not access: an installed `gh` says nothing about being
signed in (`gh auth status` — read-only — answers that), and an
`.mcp.json` entry says nothing about the server connecting. Read key
*names* from `.secrets.env` if you must; never a value.

Claude Design cannot be detected at all — it lives in the owner's
Claude account, not on disk. Ask.

## 2. Ask — one question per item

- Found: "`gh` is here and signed in as X — use it for PRs and issue
  triage? Record it?"
- Missing: "`uvx` is absent, so serena (LSP navigation) will not
  start. Install it later, or park it?"

One item, one question, plain answer. Do not bundle five into a
paragraph and do not infer consent from silence.

## 3. Record — three destinations

- `OPS.md` → **Access registry**: replace each `(fill in: …)`
  placeholder with the real name, and add a line for the design tool
  and one for second-opinion models. Names only; values stay in
  `.secrets.env`.
- `PARKED.md`: anything the owner defers, one line with the resume
  plan ("ask again when we need a second model").
- `BACKLOG.md`: anything he wants set up —
  `- [ ] P2 | kernel | install uvx so serena starts | src:install`.

## Claude Design

The owner designs; the agent ports. `/design` drafts artboards on a
canvas; `/design-login` then `/design-sync` (Claude Code 2.1.234 or
later) connect the repo's design system so the canvas uses the
product's real tokens. The exported
canvas (`.dc.html`) is the input to skill `design-port`. Record
whether the owner has it, and which project holds the current canon.

## Second opinion (codex / gemini)

If present and signed in, record them as available for an external
second opinion **the owner may ask for**. The kernel never invokes
them by itself: another model's answer is a claim, not a verdict, and
spending the owner's other subscriptions is his call, not yours.
