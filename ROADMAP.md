# Keel — roadmap and decisions

Decisions that bind future releases, so a question settled once is not
reopened by the next audit. What changed in each release is in
[CHANGELOG](CHANGELOG.md); this file holds the reasoning.

## The bar for a kernel change

Something enters the kernel when it stopped a real incident or closed a
pain that repeated — never because it is available or fashionable. A rule
in the contract, a step in a skill, a hook, a test that pins a bug that
shipped. Zero runtime services, no MCP server of its own, no ceremony on
small work. The kernel is expected to shrink as models improve: every
hook and rule encodes an assumption about what the model cannot do on its
own, and those assumptions go stale. The `OPS.md` duty "kernel
assumptions review" exists to retire them.

Two rules about the kernel's own code. A script in the kernel is a
deterministic converter or a check with a yes/no answer — input in,
output out: `anchors.sh`, `graph.sh`, `sweep.sh`, `sweep.mjs`, the hooks,
and one launcher, `safe-run.sh`.
A check of meaning is written as an instruction to the agent in a skill,
never as a script that guesses. And a number the docs quote is measured
by `test/metrics.sh` and pinned by the suite, because five releases in a
row shipped a stale one; the exact self-test count is not quoted at all,
it differs by machine, so the docs say "over 400".

## Decisions 1.8.0 (2026-09)

- **Auto memory stays on.** Claude Code's own memory
  (`~/.claude/projects/<project>/memory/`) is not disabled. It is
  machine-local and outside the repository, so what should outlive the
  project is moved into `memory/` by skill `remember`, and skill
  `adopt-feedback` sweeps your corrections out of it — on a
  monthly `OPS.md` duty, so the bridge is scheduled, not merely
  available. Redirecting it into `memory/` with `autoMemoryDirectory`
  was rejected: the value must be an absolute path, so it cannot ship
  with the repository, and both mechanisms want their own `MEMORY.md`
  format.
- **The two-attempts rule has a hook, and the hook only speaks.**
  `loop-guard` counts identical failures of one command within a
  session and, on the third, puts one sentence into context. It never
  blocks: a re-run after a real fix is the same command, and its
  discriminator — the same first error line — is a heuristic. It
  tallies its own firings; the measure at 1.9 is whether a firing is
  followed by a backlog line, a `/clear` or a change of approach.
  Firing more than once per session on average means the threshold
  rises or the hook goes.
- **The index has a hook on the same terms.** `index-guard` says when
  `memory/MEMORY.md` passes 250 lines or one line passes 300
  characters — the harness does the same for its own memory file.
  Advisory, one sentence, only on a write that crossed the line.
- **`.secrets.env` is unread by construction.** The kernel's settings
  carry `permissions.deny: Read(./.secrets.env)`. Measured on Claude
  Code 2.1.87: the Read tool and `cat` are refused, a `grep -r` from
  the directory is not (documented; the sandbox closes that when you turn it on, and it picks the same path up). Newer versions
  also refuse Write and Edit of the file, so you fill it by
  hand — the intended division anyway. Unparked.
- **The skill listing gets a budget line.** `skillListingBudgetFraction:
  0.02`. Keel's 36 listed descriptions are about 2k tokens; the
  documented default budget is 1% of the context window, 2k tokens on
  a 200k model, before the bundled skills are counted; overflow drops
  descriptions silently, least-invoked first, which on a fresh install
  is any of them. The key is documented; the CLI that built 1.8.0
  (2.1.87) does not know it yet and ignores it.
- **Scripts get `allowed-tools`.** The five skills that run a kernel
  script name it in their front-matter, so the sanctioned path costs no
  permission prompt; the bundle test checks that each named path
  exists.
- **Stop-hook gate — experiment, not shipped.** A hook on `Stop` can
  refuse a turn that claims "done" without evidence. The docs now
  describe an `agent` hook that reads files, which removes the
  transcript-only objection but costs a subagent per turn; the harness
  still lifts the gate after eight blocks in a row. The shape worth
  trying is a hook declared in the `stage` skill's front-matter with
  `once`, so it exists only for big work and dies with the stage.
  Ships when a measurement shows at most one false block per twenty
  turns of small work.
- **Verifier receipt — designed for 1.9, not shipped.** A `Stop` hook in
  `verifier.md`'s front-matter (the harness turns it into
  `SubagentStop`) can write `.qa/verdicts/<agent_id>`, and
  `verdict-guard` could then demand the receipt instead of an
  id-shaped string. Not yet: agent front-matter hooks run only after
  the workspace trust dialog, and a receipt from another machine would
  block a legitimate report. The escape hatch is designed before it
  becomes a guard.
- **Domain skills stay.** All 31 landed in one commit and no project
  has run long enough to show which are dead; `OPS.md` maps nineteen
  duties to eighteen of them. A project that wants a shorter listing sets
  `skillOverrides` in its own settings; the kernel is not cut on a
  guess. First candidate for retirement at the first `/skill-doctor`
  run: `e2e-playwright-cli`, since the CLI now ships `/verify` and
  `/run` for the same job.
- **Models on agents.** `verifier` runs on opus, `scout` on sonnet — the
  judge must not inherit whatever the session happens to run on. A project
  can override every agent with `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`.
- **No plugin packaging.** A plugin's skills are namespaced
  (`/keel:audit`), and the docs are silent on whether a plugin's
  `CLAUDE.md` loads as project context. The contract is the kernel; it
  has to be there always.
- **`OPS.md` live mode is not scheduled by the kernel.** The five ways
  Claude Code offers (`/loop` in an open session, system cron with
  `claude -p`, Desktop scheduled tasks, cloud routines, GitHub Actions)
  differ in what they can reach; `OPS.md` names them and you
  pick. No `SessionStart` ritual prints anything on the happy path.
- **site-sweep does not ship a crawler.** The skill describes the crawl
  and the output contract; the crawler is written per project on top of
  `qa-browser`'s `sweep.mjs`. Shipping 200 lines of Playwright in a
  kernel that is otherwise shell and markdown was the wrong trade.
- **No `AGENTS.md` pointer.** Importing a shared file from the contract
  saves no context (imports load in full) and makes two sources of truth.
  A project that also runs other agents copies the contract once with
  `/import`.
- **Not taken:** `paths:` and `context: fork` on skills (the listing
  cost does not change; `fork` may return for `site-sweep` on the
  context-isolation argument, not the listing one), agent `memory:` (a
  third memory), `PreCompact` hooks (asks the model to work at the
  worst moment; `recompact` recomputes the state from disk after, which
  is cheaper and always current), `SubagentStop` over the verifier (a
  judge over the judge), a `fanout-guard` that asks before an Agent
  call from a dirty tree (the prose rule in `stage` has not failed yet;
  it gets its chance), `outputStyle: Concise` for rule 11 (voice risk on
  the reports you read), Monitor, the Chrome integration, `/goal`, the
  advisor tool — each may return with a documented pain behind it.

## Closed by measurement (2026-09-12)

- **`.claude/CLAUDE.md` survives compaction.** Measured on Claude Code
  2.1.87 with a `PreCompact` hook that rewrote the contract on disk
  while the compaction ran: on the next user turn the model answered
  with the rewritten text, in both placements (`.claude/CLAUDE.md` and
  a root `CLAUDE.md`), and `InstructionsLoaded` fired for the file with
  `load_reason: compact`. Inside the turn that was compacting, the old
  text still held. No root pointer, no rules file; the placement stays.
- **The hit-test's false positives are known and gone.** Eight public
  sites in three viewports (24 pages) plus a local Astro build (18
  pages): the first run reported 12 stolen clicks, every one in one of
  three classes — a link wrapped over two lines (the centre of its box
  falls between the lines), a screen-reader-only skip link, a link cut
  off by a cell with overflow hidden. `sweep.mjs` now probes the first
  line box, skips clipped controls and clips the box to the visible
  part; the rerun reports none, and `test/fixtures/sweep.html` pins a
  real theft the sweep must still catch. `click-stolen` stays a
  candidate to confirm by eye, and so does the new `low-contrast`.
- **Hooks in a worktree.** In a session launched with `claude
  --worktree`, `CLAUDE_PROJECT_DIR` is the worktree and the worktree's
  own `.claude/settings.json` is the one read; `.worktreeinclude` did
  carry `.secrets.env`; `forkbomb-guard` denied from inside. In a
  session that enters a worktree later, the docs say the variable stays
  at the main checkout while the payload's `cwd` follows — so
  `recompact` takes the project from `cwd`, and
  `test/cases/49-worktree.sh` runs every hook with the two disagreeing.
- **Mirrored into Loft** (a commit in the loft repo, 2026-09-12): the
  WIP limit on audit findings, and "claim before you start, one
  document — one session", both in the contract; `verdict-guard` and
  `recompact` filed in loft's roadmap as the next ports.

## Open

- Reference prompts for a manual eval of the contract and the skills'
  wording: the suite covers scripts, nothing covers whether a reworded
  rule still lands. Waits for a project's real tasks to serve as the set.
- `loop-guard`'s fire rate and what follows a firing (its tally file),
  after two weeks of real sessions.
- `low-contrast` noise on the first two products: the median page
  should emit three candidates or fewer, or the threshold moves to 3.0
  and main landmarks only.
- The `.secrets.env` deny rule on a real project for a month: how often
  you edited the file by hand against how often a read was
  refused.

## Rejected for good

- A vector index, embeddings, a reranker, RAG over memory, an MCP server
  of the kernel's own — the predecessor's grave.
- Agent personas; role-play subagents.
- Per-task ceremony: run logs, hypothesis citations, locks, sidecars.
- `SessionStart` hooks that print a summary, a plan or a status every
  session. The update check prints nothing unless a newer keel exists;
  the post-compaction recovery prints two reminder lines and adds the
  state when there is any. Nothing else speaks on the happy path.
