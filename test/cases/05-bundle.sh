# Keel self-tests — 05-bundle. Sourced from test/run.sh; REPO/SK/HK/TMP and the
# helpers ok/bad/has/hasnt/section come from there.
#
# Bundle integrity: the parts read by the Claude Code harness rather than by a
# human — skill and agent frontmatter, settings.json, hook paths, model and
# disallowedTools fields. A mistake here never fails a run: the skill simply
# does not load, the agent silently gets the wrong model. Hence its own case.
#
# Parsing is stdlib python3 only (the kernel has no PyYAML and never will): the
# bundle's frontmatter is flat — `key: value` plus `- item` lists — which is
# enough. Python prints one line per assertion (`ok|…` / `fail|…`) and bash
# counts them, so the counter and the failure format stay shared with every
# other case.

section "bundle — kernel integrity"
python3 - "$REPO/bundle/.claude" > "$TMP/bundle.report" 2> "$TMP/bundle.err" <<'PY'
import json, os, re, shlex, sys

ROOT = sys.argv[1]                    # bundle/.claude
BUNDLE = os.path.dirname(ROOT)        # bundle/ — the "project" root for .claude/…

def ok(msg):  sys.stdout.write("ok|%s\n" % msg)
def bad(msg): sys.stdout.write("fail|%s\n" % " ".join(str(msg).split()))
def check(cond, msg): ok(msg) if cond else bad(msg)

def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v

def frontmatter(path):
    """Flat frontmatter: `key: value` and `- item` lists.
    Returns (data, key order, error)."""
    try:
        lines = open(path, encoding="utf-8").read().split("\n")
    except OSError as e:
        return None, None, "unreadable: %s" % e
    if not lines or lines[0].strip() != "---":
        return None, None, "frontmatter does not open with ---"
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None, None, "frontmatter does not close with ---"
    data, keys, cur = {}, [], None
    for raw in lines[1:end]:
        s = raw.rstrip()
        if not s.strip() or s.lstrip().startswith("#"):
            continue
        if s.lstrip().startswith("- "):
            if cur is None:
                return None, None, "list item before the first key"
            item = unquote(s.lstrip()[2:])
            if isinstance(data[cur], list):
                data[cur].append(item)
            elif data[cur] == "":
                data[cur] = [item]
            else:
                return None, None, "key %s has both a value and a list" % cur
            continue
        m = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$", s)
        if not m:
            return None, None, "line does not parse as `key: value`: %s" % s.strip()
        cur = m.group(1)
        if cur in data:
            return None, None, "key %s repeats" % cur
        keys.append(cur)
        data[cur] = unquote(m.group(2))
    return data, keys, None

def items(v):
    """Value as a list: a YAML list, or a scalar split on commas."""
    if isinstance(v, list):
        return [x.strip() for x in v if x.strip()]
    if v is None or not str(v).strip():
        return []
    return [x.strip() for x in str(v).split(",") if x.strip()]

def text_of(path):
    return open(path, encoding="utf-8").read()

# ── settings.json ──────────────────────────────────────────────────────────
sp = os.path.join(ROOT, "settings.json")
settings = None
try:
    settings = json.load(open(sp, encoding="utf-8"))
    ok("settings.json is valid JSON")
except Exception as e:
    bad("settings.json does not parse: %s" % e)

if isinstance(settings, dict):
    # The secrets rule says the agent never reads `.secrets.env`. Prose asked;
    # this line enforces. It was parked through 1.8.0 and unparked once a real
    # run showed what it does and does not cover.
    deny = ((settings.get("permissions") or {}).get("deny") or [])
    check("Read(./.secrets.env)" in deny,
          "settings.json: permissions.deny refuses Read(./.secrets.env) (now: %s)"
          % (", ".join(str(d) for d in deny) or "nothing"))
    hooks = settings.get("hooks")
    check(isinstance(hooks, dict) and hooks, "settings.json: hooks section is not empty")
    # Every event the kernel claims to hook. A hook whose event name is wrong
    # is not an error anywhere — it simply never fires, and the rule it was
    # meant to enforce quietly goes back to being prose.
    for event in ("PreToolUse", "SessionStart", "PostToolUseFailure", "PostToolUse"):
        groups = (hooks or {}).get(event)
        check(isinstance(groups, list) and groups,
              "settings.json: %s has at least one hook group" % event)
    seen = 0
    hooks_dir = os.path.realpath(os.path.join(ROOT, "hooks"))
    for event, groups in (hooks or {}).items():
        if not isinstance(groups, list):
            bad("settings.json: %s is not a list of groups" % event)
            continue
        for group in groups:
            for h in (group or {}).get("hooks", []):
                seen += 1
                where = "%s[%d]" % (event, seen)
                check(h.get("type") == "command", "settings.json: %s is type: command" % where)
                cmd = h.get("command") or ""
                try:
                    tokens = shlex.split(cmd)
                except ValueError:
                    tokens = []
                if not tokens:
                    bad("settings.json: %s has an empty command" % where)
                    continue
                p = tokens[0].replace("${CLAUDE_PROJECT_DIR}", BUNDLE)
                p = p.replace("$CLAUDE_PROJECT_DIR", BUNDLE)
                rp = os.path.realpath(p)
                if not os.path.isfile(rp):
                    bad("settings.json: %s points at a file that does not exist: %s" % (where, tokens[0]))
                    continue
                check(rp.startswith(hooks_dir + os.sep),
                      "settings.json: %s lives in .claude/hooks/ (%s)" % (where, os.path.basename(rp)))
                runnable = os.access(rp, os.X_OK)
                if not runnable:
                    with open(rp, "rb") as fh:
                        runnable = fh.read(2) == b"#!"
                check(runnable, "settings.json: %s — %s is executable or has a shebang" % (where, os.path.basename(rp)))
    check(seen > 0, "settings.json: hooks are listed")

# ── skills ─────────────────────────────────────────────────────────────────
# Frontmatter keys Claude Code knows. An unknown key is a typo that fails
# silently — the harness just ignores it.
SKILL_KEYS = set("""name description when_to_use argument-hint arguments
disable-model-invocation user-invocable allowed-tools disallowed-tools model
effort context agent background hooks paths shell metadata license
compatibility""".split())
# Skills the agent never reaches for on its own — only on the owner's direct
# command. This is the owner's decision; change the set, change this test.
NO_AUTO = set(["adopt-feedback", "integrations", "migrate", "site-sweep"])

skills_dir = os.path.join(ROOT, "skills")
skills = sorted(d for d in os.listdir(skills_dir) if os.path.isdir(os.path.join(skills_dir, d)))
# No literal floor here. `>= 37` was a second inventory of the same tree: it
# said 37 while the bundle shipped 40, so it stopped meaning anything the first
# time a skill was added. How many skills there are is measured by
# test/metrics.sh and compared against every place the docs claim it, in
# 01-metrics; what this case owes is that the directory is not empty.
check(len(skills) > 0, "bundle ships skills (found %d)" % len(skills))

no_auto_found = set()
for d in skills:
    p = os.path.join(skills_dir, d, "SKILL.md")
    if not os.path.isfile(p):
        bad("skills/%s: no SKILL.md" % d)
        continue
    fm, keys, err = frontmatter(p)
    if err:
        bad("skills/%s: %s" % (d, err))
        continue
    ok("skills/%s: frontmatter opens and closes with ---" % d)
    name = fm.get("name")
    check(name == d, "skills/%s: name matches the directory (name: %s)" % (d, name))
    check(isinstance(name, str) and re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", name or ""),
          "skills/%s: name is [a-z0-9-] only (name: %s)" % (d, name))
    desc = fm.get("description")
    if not isinstance(desc, str) or not desc.strip() or desc.strip() in ("|", ">", "|-", ">-", "|+", ">+"):
        bad("skills/%s: description is non-empty and on one line" % d)
    else:
        ok("skills/%s: description is non-empty and on one line" % d)
        check(len(desc) <= 1024, "skills/%s: description ≤ 1024 chars (now %d)" % (d, len(desc)))
    unknown = [k for k in (keys or []) if k not in SKILL_KEYS]
    check(not unknown, "skills/%s: frontmatter has only known keys (extra: %s)" % (d, ", ".join(unknown)))
    # allowed-tools is what spares the sanctioned command a permission prompt.
    # A path in it that does not exist grants nothing and prompts anyway — the
    # failure is a dialog the owner did not expect, not an error message.
    for entry in items(fm.get("allowed-tools")):
        if not entry.startswith("Bash("):
            continue
        for m in re.finditer(r"\.claude/(skills/[a-z0-9][a-z0-9-]*/[A-Za-z0-9_.-]+)", entry):
            check(os.path.exists(os.path.join(ROOT, m.group(1))),
                  "skills/%s: allowed-tools names .claude/%s, which the bundle ships" % (d, m.group(1)))
    if str(fm.get("disable-model-invocation", "")).lower() == "true":
        no_auto_found.add(d)
check(no_auto_found == NO_AUTO,
      "disable-model-invocation on exactly %s (now: %s)"
      % (", ".join(sorted(NO_AUTO)), ", ".join(sorted(no_auto_found)) or "nothing"))
# The verifier delegates UI verdicts to qa-browser, so the harness must be free
# to load it on the verifier's behalf.
qa = os.path.join(skills_dir, "qa-browser", "SKILL.md")
if os.path.isfile(qa):
    fm, _keys, err = frontmatter(qa)
    check(not err and str((fm or {}).get("disable-model-invocation", "")).lower() != "true",
          "skills/qa-browser: model invocation stays enabled (the verifier calls it)")

# ── agents ─────────────────────────────────────────────────────────────────
AGENT_KEYS = set("""name description tools disallowedTools model effort
permissionMode skills memory mcpServers maxTurns background isolation hooks
color""".split())
MODELS = set(["opus", "sonnet", "haiku", "fable", "inherit"])
EFFORTS = set(["low", "medium", "high", "xhigh", "max"])

agents_dir = os.path.join(ROOT, "agents")
agents = sorted(f for f in os.listdir(agents_dir) if f.endswith(".md"))
check(set(a[:-3] for a in agents) == set(["scout", "verifier"]),
      "bundle agents are scout and verifier (now: %s)" % ", ".join(a[:-3] for a in agents))

fms = {}
for f in agents:
    stem = f[:-3]
    fm, keys, err = frontmatter(os.path.join(agents_dir, f))
    if err:
        bad("agents/%s: %s" % (f, err))
        continue
    fms[stem] = fm
    ok("agents/%s: frontmatter opens and closes with ---" % f)
    check(fm.get("name") == stem, "agents/%s: name matches the filename (name: %s)" % (f, fm.get("name")))
    unknown = [k for k in (keys or []) if k not in AGENT_KEYS]
    check(not unknown, "agents/%s: frontmatter has only known keys (extra: %s)" % (f, ", ".join(unknown)))
    model = str(fm.get("model", ""))
    check(model in MODELS or model.startswith("claude-"),
          "agents/%s: model is known or a full claude-… id (model: %s)" % (f, model or "none"))
    if "effort" in fm:
        check(str(fm["effort"]) in EFFORTS,
              "agents/%s: effort is one of %s (effort: %s)" % (f, "/".join(sorted(EFFORTS)), fm["effort"]))

scout = fms.get("scout")
if scout is None:
    bad("agents/scout.md: frontmatter did not parse — scout checks skipped")
else:
    check(scout.get("model") == "sonnet", "scout: model sonnet (reconnaissance is not worth opus)")
    dis = items(scout.get("disallowedTools"))
    for t in ("Write", "Edit", "NotebookEdit"):
        check(t in dis, "scout: disallowedTools contains %s (scout changes nothing)" % t)
    tools = items(scout.get("tools"))
    for t in ("Write", "Edit", "NotebookEdit"):
        check(t not in tools, "scout: %s is not in tools" % t)
verifier = fms.get("verifier")
if verifier is None:
    bad("agents/verifier.md: frontmatter did not parse — verifier checks skipped")
else:
    check(verifier.get("model") == "opus", "verifier: model opus (the verdict is judged by opus)")
    check("qa-browser" in items(verifier.get("skills")),
          "verifier: skills includes qa-browser (UI verdicts run the browser pass)")

# ── stale references ───────────────────────────────────────────────────────
# A contract rule number goes stale at the first renumbering, and the prose
# that cites it then points at the wrong rule with full confidence.
RULE_RX = re.compile(r"\brule\s*(№\s*)?\d", re.I)
scanned = []
for base in ("skills", "agents", "hooks"):
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, base)):
        for f in files:
            if f.endswith((".md", ".sh", ".mjs", ".py")):
                scanned.append(os.path.join(dirpath, f))
hits = []
for p in sorted(scanned):
    for n, line in enumerate(text_of(p).split("\n"), 1):
        if RULE_RX.search(line):
            hits.append("%s:%d" % (os.path.relpath(p, ROOT), n))
check(not hits, "no contract-rule numbers cited in skills, agents, hooks or scripts: %s" % ", ".join(hits))

# ── skill mentions resolve to directories ──────────────────────────────────
# Rename a skill, forget the prose, and every reference to it becomes a lie.
known = set(skills)
claude_md = os.path.join(ROOT, "CLAUDE.md")
prose = [os.path.join(skills_dir, d, "SKILL.md") for d in skills]
prose += [os.path.join(agents_dir, f) for f in agents]
prose = [p for p in prose if os.path.isfile(p)]
missing = []
for p in prose + [claude_md]:
    if not os.path.isfile(p):
        continue
    for m in re.finditer(r"[Ss]kills?\s+`/?([a-z0-9][a-z0-9-]*)`", text_of(p)):
        if m.group(1) not in known:
            missing.append("%s → %s" % (os.path.relpath(p, ROOT), m.group(1)))
check(not missing, "every `skill \\`name\\`` mention resolves to a skills/ directory (missing: %s)"
      % ", ".join(missing))

# ── the contract routes to the skills ──────────────────────────────────────
# A skill nobody is routed to is a skill nobody uses — the way the predecessor's
# catalogue died. The contract is the only file always in context, so it is the
# only place a routing line can be read before the work starts. Any bare
# back-ticked name that matches a skill directory counts as routing.
routed = set()
if os.path.isfile(claude_md):
    for m in re.finditer(r"`/?([a-z0-9][a-z0-9-]*)`", text_of(claude_md)):
        if m.group(1) in known:
            routed.add(m.group(1))
# The contract names only the skills a session must route through; the rest
# load from the listing. Those six are load-bearing: a typo in one of them
# silently unhooks a rule.
CORE_ROUTED = {"stage", "recall", "remember", "qa-browser", "audit", "safe-dev-server"}
check(CORE_ROUTED <= routed,
      "the contract routes to the six core skills (missing: %s)" % (", ".join(sorted(CORE_ROUTED - routed)) or "none"))

# ── script paths in skill bodies resolve ───────────────────────────────────
# A SKILL.md that hands the agent a path is handing it a command to run; a path
# that does not exist turns the whole procedure into a dead end at step one.
missing = []
for d in skills:
    p = os.path.join(skills_dir, d, "SKILL.md")
    if not os.path.isfile(p):
        continue
    for m in re.finditer(r"\.claude/skills/([a-z0-9][a-z0-9-]*)/([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*)", text_of(p)):
        rel = os.path.join("skills", m.group(1), m.group(2))
        if not os.path.exists(os.path.join(ROOT, rel)):
            missing.append("skills/%s → .claude/%s" % (d, rel))
check(not missing, "every .claude/skills/<x>/<file> path in a SKILL.md exists (missing: %s)"
      % ", ".join(sorted(set(missing))))
PY
if [ -s "$TMP/bundle.err" ]; then
  bad "bundle parse crashed: $(tr '\n' ' ' < "$TMP/bundle.err" | tail -c 200)"
fi

# ── the installer counts the bundle, it does not remember a number ──────────
# install.sh used to self-check against `-ge 37` while the bundle shipped 40:
# a second inventory of the same tree, already wrong, and one that would have
# waved a half-copied bundle of 38 skills through. The expected count is read
# from the bundle being installed, so the check cannot drift from what it checks.
grep -nE '\-ge [0-9]' "$REPO/install.sh" >/dev/null 2>&1 \
  && bad "install.sh carries a literal count floor: $(grep -nE '\-ge [0-9]' "$REPO/install.sh" | tr '\n' ' ')" \
  || ok
grep -q 'ls "$SRC/bundle/.claude/skills"' "$REPO/install.sh" \
  && ok || bad "install.sh derives the expected skill count from the source bundle"
grep -q '\[ "\$n_skills" = "\$n_skills_src" \]' "$REPO/install.sh" \
  && ok || bad "install.sh self-check compares installed skills against the bundle's count"
[ -s "$TMP/bundle.report" ] || bad "bundle parse produced no assertions at all"
while IFS= read -r line; do
  case "$line" in
    "ok|"*) ok ;;
    *)      bad "${line#fail|}" ;;
  esac
done < "$TMP/bundle.report"
