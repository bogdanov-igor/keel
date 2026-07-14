---
name: visual-memory
description: Turn a screenshot or PDF page into searchable memory by writing a structured text description as a plain note under memory/ plus one MEMORY.md index line — retrievable later by grep, no image infrastructure.
---

# visual-memory

The image is not the memory — the text description is. A screenshot stored as
pixels is invisible to grep; a specific, verbatim description of what it shows
is findable forever. This skill converts one image into that description.

## Inputs

| Field | Required | Description |
|---|---|---|
| image | yes | Absolute path to a screenshot or PDF-page PNG |
| source | yes | Where it came from (URL, app, document, context) — recorded for provenance |
| slug | yes | kebab-case id for the note (and the image file) |
| links | no | Related note slugs, rendered as `[[wikilinks]]` |

## Steps

1. **Get the image.** Use the provided path. If a browser capture is needed,
   take it via skill qa-browser (Playwright CLI script, screenshot lands under
   `.qa/`), then copy the PNG to `memory/visual/img/<slug>.png`. For a PDF,
   either read the page directly or render it to PNG first.
2. **Describe it.** Look at the image and write a structured, specific
   description — this text is the searchable memory, so be concrete:
   - one line: purpose / what the screen or page shows;
   - verbatim key text: labels, values, error messages, headings — the exact
     strings someone would later grep for;
   - notable UI elements, states, numbers, anomalies;
   - source, context, and capture date.
   A thin "a screenshot of a page" description is a failure — grep will never
   surface it.
3. **Write the note.** Create `memory/visual/<slug>.md` with a small
   frontmatter block (`created`, `source`, `image: img/<slug>.png`), the
   description body, and any `[[wikilinks]]`. Add exactly one index line to
   `memory/MEMORY.md`, following the same one-line format skill remember uses:
   topic words first, so a later grep of the index hits it.
4. **Check retrievability.** Grep `memory/` for two or three natural terms a
   future session would use (an error string, a feature name — not the slug or
   title). The note must come back. If it does not, the description is missing
   the words that matter; enrich it and re-check.
5. **If it taught a lesson.** When the screenshot evidences a reusable insight
   or a trap (not just a state worth remembering), also record that takeaway
   via skill remember — the visual note holds the evidence, the lesson holds
   the conclusion, and they link to each other.

## Done when

- Note exists under `memory/visual/` with a specific description and provenance
  frontmatter, plus exactly one `MEMORY.md` index line.
- A natural-language grep (not the exact title) finds the note.
- Not done: description is generic, the note is not grep-retrievable, or the
  note was written outside `memory/visual/`.
- If the image is unreadable or corrupt, say so and stop — do not write a
  guessed description.

## Anti-patterns

- Relying on the image file as the memory. Nothing searches pixels here; if a
  detail is not in the text, it is lost.
- Generic descriptions. Capture the specific strings, values, and error codes
  that make the screen findable later.
- Placing visual notes outside `memory/visual/` — one home keeps grep scopes
  and the image directory predictable.
- Committing raw image binaries. `memory/visual/img/` stays gitignored; the
  committed artifact is the text.
- Standing up any image-embedding or vision-indexing service. The whole point
  of this design is zero infrastructure: text note + index line + grep.
- Leaving a browser running after capture. Captures go through skill
  qa-browser's scripted flow, which opens and closes its own browser.
