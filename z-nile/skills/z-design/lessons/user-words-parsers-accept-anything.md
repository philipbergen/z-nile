---
title: A check over text the user wrote verbatim accepts anything they can write
when: design
tags: [parsers, verbatim, capture]
check: Can the user's own words, unedited (a pasted plan with `## ` headings, a code fence, a line that looks like a field), break the parser or the audit that judges the file holding them, or are they held in a container the parser skips?
---
A rule that keeps the user's words "exactly as written" and a parser that reads structure from the same file collide when the words contain structure. The check then forces the author to edit what must not be edited.

**Why:** c0260 design review 001 F3: `capture/ask.md` split into sections at every `## ` line, so a pasted plan could never pass the audit unless its headings were removed.

**How to apply:** put verbatim text in a fenced block (fence longer than any run inside), make the parser skip fenced lines, refuse an unclosed fence, and add a spec case whose verbatim text holds headings, fences and field-like lines.
