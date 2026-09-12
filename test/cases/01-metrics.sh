# Keel self-tests — 01-metrics. Sourced from test/run.sh; REPO/SK/HK/TMP and the
# helpers ok/bad/has/hasnt/section come from there.
#
# Every release since 1.4.0 shipped a stale number in the documentation — the
# contract's line count, the shell totals, the bundle size, the skill count —
# because each was re-measured by hand and the hand skipped a file. The 1.8.0
# docs pass repeated it: the guides said 93 lines where the contract had 94.
# So the numbers are measured by test/metrics.sh and every place that quotes
# one is listed below. A claim that no longer matches the tree fails here
# instead of shipping; a claim that was reworded fails LOUDLY rather than
# passing silently, because a regex that matches nothing is the exact way a
# gate like this rots into decoration.
#
# The table is `key | file | extended regex with exactly one capture group`.
# Files are read with every run of whitespace collapsed to one space, so a
# claim that the paragraph wrapped across two lines still matches. Thousands
# separators — "5,170" and "5 170" — are stripped from both sides before the
# comparison; the two languages write them differently and neither is wrong.
#
# The one number deliberately NOT pinned is the self-test count: it differs by
# machine (gnu-tar present or not), so the docs say "over 400" / "более 400"
# and the exact figure lives in the CHANGELOG and in the run. The last block
# here holds that line.

section "docs — numbers match the tree"
bash "$REPO/test/metrics.sh" > "$TMP/metrics.txt" 2> "$TMP/metrics.err"
if [ -s "$TMP/metrics.err" ]; then
  bad "test/metrics.sh wrote to stderr: $(tr '\n' ' ' < "$TMP/metrics.err" | tail -c 200)"
fi
[ -s "$TMP/metrics.txt" ] && ok || bad "test/metrics.sh printed no metrics at all"

python3 - "$TMP/metrics.txt" "$REPO" > "$TMP/metrics.report" 2> "$TMP/metrics.pyerr" <<'PY'
import os, re, sys

metrics_path, ROOT = sys.argv[1], sys.argv[2]

def ok(msg):  sys.stdout.write("ok|%s\n" % msg)
def bad(msg): sys.stdout.write("fail|%s\n" % " ".join(str(msg).split()))

metrics = {}
for line in open(metrics_path, encoding="utf-8"):
    line = line.strip()
    if "=" in line:
        k, v = line.split("=", 1)
        metrics[k.strip()] = v.strip()

# key | file | regex with exactly one capture group. N = a number that may
# carry a thousands separator; the group keeps it and the comparison strips it.
TABLE = r"""
contract_lines         | README.md | contract-([0-9][0-9, ]*)%20lines
contract_lines         | README.md | alt="([0-9][0-9, ]*)-line contract"
contract_lines         | README.md | CLAUDE\.md\): ([0-9][0-9, ]*) lines
skills                 | README.md | skills-([0-9][0-9, ]*)-success
skills                 | README.md | alt="([0-9][0-9, ]*) skills"
skills                 | README.md | - ([0-9][0-9, ]*) lazily loaded skills
bundle_kb              | README.md | kernel-([0-9][0-9, ]*)%20KB
bundle_files           | README.md | %20KB%20%C2%B7%20([0-9][0-9, ]*)%20files
bundle_kb              | README.md | alt="([0-9][0-9, ]*) KB,
bundle_files           | README.md | KB, ([0-9][0-9, ]*) files"

contract_lines         | README.ru.md | %D0%BA%D0%BE%D0%BD%D1%82%D1%80%D0%B0%D0%BA%D1%82-([0-9][0-9, ]*)%20
contract_lines         | README.ru.md | alt="контракт ([0-9][0-9, ]*) строк[аи]?"
contract_lines         | README.ru.md | CLAUDE\.md\): ([0-9][0-9, ]*) строк[аи]?
skills                 | README.ru.md | %D1%81%D0%BA%D0%B8%D0%BB%D0%BB%D0%BE%D0%B2-([0-9][0-9, ]*)-success
skills                 | README.ru.md | alt="([0-9][0-9, ]*) скилл[аов]*"
skills                 | README.ru.md | - ([0-9][0-9, ]*) скилл[аов]* с ленивой загрузкой
bundle_kb              | README.ru.md | %D1%8F%D0%B4%D1%80%D0%BE-([0-9][0-9, ]*)%20%D0%9A%D0%91
bundle_files           | README.ru.md | %20%D0%9A%D0%91%20%C2%B7%20([0-9][0-9, ]*)%20%D1%84%D0%B0%D0%B9%D0%BB
bundle_kb              | README.ru.md | alt="([0-9][0-9, ]*) КБ,
bundle_files           | README.ru.md | КБ, ([0-9][0-9, ]*) файл[аов]*"

contract_lines         | docs/en/architecture.md | CLAUDE\.md\) — ([0-9][0-9, ]*) lines, always in
contract_lines         | docs/en/architecture.md | it stands at ([0-9][0-9, ]*) today
skills                 | docs/en/architecture.md | ([0-9][0-9, ]*) markdown procedures under
skills                 | docs/en/architecture.md | descriptions\* of all ([0-9][0-9, ]*) load
maintainer_shell_lines | docs/en/architecture.md | maintainer-only — ([0-9][0-9, ]*) of the kernel
shell_lines            | docs/en/architecture.md | kernel's ([0-9][0-9, ]*) lines of shell

contract_lines         | docs/ru/architecture.md | CLAUDE\.md\) — ([0-9][0-9, ]*) строк[аи]?, всегда в
contract_lines         | docs/ru/architecture.md | сегодня в нём ([0-9][0-9, ]*)
skills                 | docs/ru/architecture.md | ([0-9][0-9, ]*) markdown-процедур в
skills                 | docs/ru/architecture.md | Описания\* всех ([0-9][0-9, ]*) грузятся
maintainer_shell_lines | docs/ru/architecture.md | инструмент мейнтейнера: ([0-9][0-9, ]*) строк[аи]? из
shell_lines            | docs/ru/architecture.md | строк[аи]? из ([0-9][0-9, ]*) строк[аи]? shell в ядре

contract_lines         | docs/en/why-keel.md | `CLAUDE\.md` = ([0-9][0-9, ]*) lines
contract_chars         | docs/en/why-keel.md | lines / ([0-9][0-9, ]*) chars \(~1[.]?[0-9]k
shell_lines            | docs/en/why-keel.md | ([0-9][0-9, ]*) lines of shell across [0-9][0-9, ]* files\. Shipped
shell_files            | docs/en/why-keel.md | lines of shell across ([0-9][0-9, ]*) files\. Shipped
shipped_shell_lines    | docs/en/why-keel.md | Shipped: ([0-9][0-9, ]*) lines across
shipped_shell_files    | docs/en/why-keel.md | Shipped: [0-9][0-9, ]* lines across ([0-9][0-9, ]*) files
hooks                  | docs/en/why-keel.md | the installer, ([0-9][0-9, ]*) hooks
mjs_lines              | docs/en/why-keel.md | plus ([0-9][0-9, ]*) lines of JavaScript
maintainer_shell_lines | docs/en/why-keel.md | Maintainer-only: ([0-9][0-9, ]*) lines across
maintainer_shell_files | docs/en/why-keel.md | Maintainer-only: [0-9][0-9, ]* lines across ([0-9][0-9, ]*) files
bundle_kb              | docs/en/why-keel.md | 4\.3 MB / 133 files \| ([0-9][0-9, ]*) KB
bundle_files           | docs/en/why-keel.md | 4\.3 MB / 133 files \| [0-9][0-9, ]* KB / ([0-9][0-9, ]*) files
shell_lines            | docs/en/why-keel.md | per-zone cases: ([0-9][0-9, ]*) lines across
shell_files            | docs/en/why-keel.md | per-zone cases: [0-9][0-9, ]* lines across ([0-9][0-9, ]*) files
shipped_shell_lines    | docs/en/why-keel.md | and ([0-9][0-9, ]*) lines across [0-9][0-9, ]* files if only
shipped_shell_files    | docs/en/why-keel.md | and [0-9][0-9, ]* lines across ([0-9][0-9, ]*) files if only
contract_lines         | docs/en/why-keel.md | it stands at ([0-9][0-9, ]*) today
maintainer_shell_lines | docs/en/why-keel.md | maintainer tool — ([0-9][0-9, ]*) of the
shell_lines            | docs/en/why-keel.md | maintainer tool — [0-9][0-9, ]* of the ([0-9][0-9, ]*) lines
contract_lines         | docs/en/why-keel.md | 15,245 against ([0-9][0-9, ]*) /
contract_chars         | docs/en/why-keel.md | 15,245 against [0-9][0-9, ]* / ([0-9][0-9, ]*)
shell_lines            | docs/en/why-keel.md | 6,316 / 17 files against ([0-9][0-9, ]*) /
shell_files            | docs/en/why-keel.md | 6,316 / 17 files against [0-9][0-9, ]* / ([0-9][0-9, ]*)
shipped_shell_lines    | docs/en/why-keel.md | shipped part of it alone — ([0-9][0-9, ]*) lines across
shipped_shell_files    | docs/en/why-keel.md | shipped part of it alone — [0-9][0-9, ]* lines across ([0-9][0-9, ]*) files
bundle_kb              | docs/en/why-keel.md | 3,796 files against ([0-9][0-9, ]*) KB
bundle_files           | docs/en/why-keel.md | 3,796 files against [0-9][0-9, ]* KB / ([0-9][0-9, ]*)

contract_lines         | docs/ru/why-keel.md | `CLAUDE\.md` = ([0-9][0-9, ]*) строк[аи]?
contract_chars         | docs/ru/why-keel.md | строк[аи]? / ([0-9][0-9, ]*) символов \(~1[,]?[0-9]k
shell_lines            | docs/ru/why-keel.md | ([0-9][0-9, ]*) строк[аи]? shell в [0-9][0-9, ]* файл(?:ах|е)\. Уезжает
shell_files            | docs/ru/why-keel.md | строк[аи]? shell в ([0-9][0-9, ]*) файл(?:ах|е)\. Уезжает
shipped_shell_lines    | docs/ru/why-keel.md | Уезжает в проект: ([0-9][0-9, ]*) строк[аи]?
shipped_shell_files    | docs/ru/why-keel.md | Уезжает в проект: [0-9][0-9, ]* строк[аи]? в ([0-9][0-9, ]*) файл(?:ах|е)
hooks                  | docs/ru/why-keel.md | установщик, ([0-9][0-9, ]*) хук[аов]*
mjs_lines              | docs/ru/why-keel.md | плюс ([0-9][0-9, ]*) строк[аи]? JavaScript
maintainer_shell_lines | docs/ru/why-keel.md | Только для мейнтейнера: ([0-9][0-9, ]*) строк[аи]?
maintainer_shell_files | docs/ru/why-keel.md | Только для мейнтейнера: [0-9][0-9, ]* строк[аи]? в ([0-9][0-9, ]*) файл(?:ах|е)
bundle_kb              | docs/ru/why-keel.md | 133 файла \| ([0-9][0-9, ]*) КБ
bundle_files           | docs/ru/why-keel.md | 133 файла \| [0-9][0-9, ]* КБ / ([0-9][0-9, ]*) файл[аов]*
shell_lines            | docs/ru/why-keel.md | разложенный по зонам: ([0-9][0-9, ]*) строк[аи]? в
shell_files            | docs/ru/why-keel.md | разложенный по зонам: [0-9][0-9, ]* строк[аи]? в ([0-9][0-9, ]*) файл(?:ах|е)
shipped_shell_lines    | docs/ru/why-keel.md | — и ([0-9][0-9, ]*) строк[аи]? в [0-9][0-9, ]* файл(?:ах|е), если считать
shipped_shell_files    | docs/ru/why-keel.md | — и [0-9][0-9, ]* строк[аи]? в ([0-9][0-9, ]*) файл(?:ах|е), если считать
contract_lines         | docs/ru/why-keel.md | сегодня в нём ([0-9][0-9, ]*)
shell_lines            | docs/ru/why-keel.md | из ([0-9][0-9, ]*) строк[аи]? ядра
maintainer_shell_lines | docs/ru/why-keel.md | строк[аи]? ядра ([0-9][0-9, ]*) — только для мейнтейнера
shipped_shell_lines    | docs/ru/why-keel.md | в проект уходит ([0-9][0-9, ]*) строк[аи]?
shipped_shell_files    | docs/ru/why-keel.md | в проект уходит [0-9][0-9, ]* строк[аи]? в ([0-9][0-9, ]*) файл(?:ах|е)
contract_lines         | docs/ru/why-keel.md | 15 245 против ([0-9][0-9, ]*) /
contract_chars         | docs/ru/why-keel.md | 15 245 против [0-9][0-9, ]* / ([0-9][0-9, ]*)
shell_lines            | docs/ru/why-keel.md | 6 316 строк в 17 файл(?:ах|е) против ([0-9][0-9, ]*) в
shell_files            | docs/ru/why-keel.md | 6 316 строк в 17 файл(?:ах|е) против [0-9][0-9, ]* в ([0-9][0-9, ]*)
shipped_shell_lines    | docs/ru/why-keel.md | поставляемая часть — ([0-9][0-9, ]*) строк[аи]?
shipped_shell_files    | docs/ru/why-keel.md | поставляемая часть — [0-9][0-9, ]* строк[аи]? в ([0-9][0-9, ]*) файл(?:ах|е)
bundle_kb              | docs/ru/why-keel.md | 3 796 файлов против ([0-9][0-9, ]*) КБ
bundle_files           | docs/ru/why-keel.md | 3 796 файлов против [0-9][0-9, ]* КБ / ([0-9][0-9, ]*)

contract_lines         | docs/assets/architecture.svg | ([0-9][0-9, ]*) lines · always in context
skills                 | docs/assets/architecture.svg | skills/ — ([0-9][0-9, ]*), lazy-loaded
contract_lines         | docs/assets/architecture.ru.svg | ([0-9][0-9, ]*) строк[аи]? · всегда в контексте
skills                 | docs/assets/architecture.ru.svg | skills/ — ([0-9][0-9, ]*), ленивая загрузка
"""

SEPARATORS = ",\u00a0\u2009\u202f \t"   # comma, nbsp, thin and narrow spaces, space, tab

def norm(s):
    return "".join(ch for ch in s if ch not in SEPARATORS)

_text = {}
def text(rel):
    if rel not in _text:
        try:
            raw = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        except OSError as e:
            _text[rel] = None
            bad("cannot read %s: %s" % (rel, e))
        else:
            # one long line: a claim that wrapped mid-sentence still matches
            _text[rel] = re.sub(r"\s+", " ", raw)
    return _text[rel]

checked = 0
for row in TABLE.strip().split("\n"):
    if not row.strip():
        continue
    parts = row.split("|", 2)
    if len(parts) != 3:
        bad("metrics table row does not parse: %s" % row)
        continue
    key, rel, rx = (p.strip() for p in parts)
    if key not in metrics:
        bad("metrics table row names %s, which test/metrics.sh does not print" % key)
        continue
    try:
        pat = re.compile(rx)
    except re.error as e:
        bad("row %s / %s: regex does not compile: %s" % (key, rel, e))
        continue
    if pat.groups != 1:
        bad("row %s / %s: regex has %d capture groups, needs exactly 1" % (key, rel, pat.groups))
        continue
    body = text(rel)
    if body is None:
        continue
    hits = pat.findall(body)
    checked += 1
    if not hits:
        # Loud on purpose. A silent skip here is how the gate stops gating:
        # the sentence gets reworded, the regex stops matching, and a stale
        # number rides into the next release with a green suite behind it.
        bad("claim not found in %s — reworded? update the row or the doc (%s: /%s/)" % (rel, key, rx))
        continue
    want = norm(metrics[key])
    wrong = sorted(set(norm(h) for h in hits if norm(h) != want))
    if wrong:
        bad("%s claims %s = %s, measured %s (/%s/)" % (rel, key, "/".join(wrong), want, rx))
    else:
        ok("%s: %s = %s" % (rel, key, want))

if checked < 80:
    # Not a claim about the docs: a claim about this table. Deleting rows is the
    # cheapest way to make this case green, and the one that puts the docs back
    # exactly where they were before it existed.
    bad("only %d claims were checked — rows went missing from the table" % checked)
else:
    ok("%d documented numbers compared against the tree" % checked)

# ── the exact self-test count is not a documented number ───────────────────
# It differs by machine: the gnu-tar block of 90-build-archive runs only where
# gnu-tar is installed, so the same tree honestly reports two different totals.
# A figure that cannot be reproduced by the reader does not belong in the docs;
# "over 400" / "более 400" does, and the exact number lives in the CHANGELOG
# and in the output of the run.
COUNT = re.compile(r"(?<!over )(?<!than )(?<!более )(?<!свыше )[0-9]{3,4}\s*(?:assertions?|self-tests?|tests?\b|ассерт\w*|самотест\w*|тест\w*)")
docs = ["README.md", "README.ru.md", "ROADMAP.md"]
for lang in ("en", "ru"):
    d = os.path.join(ROOT, "docs", lang)
    docs += ["docs/%s/%s" % (lang, f) for f in sorted(os.listdir(d)) if f.endswith(".md")]
stated = []
for rel in docs:
    body = text(rel)
    if body is None:
        continue
    for m in COUNT.finditer(body):
        stated.append("%s → %s" % (rel, m.group(0)))
if stated:
    bad("a doc states an exact self-test count, which differs by machine: %s" % ", ".join(stated))
else:
    ok("no doc states an exact self-test count (they say over 400 / более 400)")
PY
if [ -s "$TMP/metrics.pyerr" ]; then
  bad "metrics comparison crashed: $(tr '\n' ' ' < "$TMP/metrics.pyerr" | tail -c 300)"
fi
[ -s "$TMP/metrics.report" ] || bad "metrics comparison produced no assertions at all"
while IFS= read -r line; do
  case "$line" in
    "ok|"*) ok ;;
    *)      bad "${line#fail|}" ;;
  esac
done < "$TMP/metrics.report"
