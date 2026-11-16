---
title: A format holds every repeat, and its parser refuses ambiguity
when: both
tags: [parsers, formats, data-loss]
check: Can this format hold every repeat of what it records (several sources, several values), and does its parser refuse a repeated or ambiguous field instead of silently keeping one?
---
A record shaped for one value loses the second one, and a parser that keeps the last of two keys loses the first without a word. Both look fine in every test that writes one value. Give repeatable things a repeatable form (a list or one entry per value), and make the parser name a repeated single-value field as a problem.

**Why:** R0040 design review 4 (F1): a lesson's non-review source was a single `from:` key. A second source (another stream, a second correction by the user) had nowhere to go, and the frontmatter parser silently kept the last of two `from:` lines, so recurring lessons could never show their count, and `--check` stayed green.

**How to apply:** for each field of a new format, ask "can there be two?". If yes, give it a repeatable form. If no, add a spec case where it appears twice and must be refused.

c0120 code review 011 F5: `busyRefs` shortened `refs/heads/origin/x` and `refs/remotes/origin/x` both to `origin/x`, and the exemption then stripped `origin/` from either, so a local branch named `origin/proto-c0117` matched an approved name it doesn't have. Keep the full refname until the last step that needs it, and strip a prefix only from the namespace it belongs to.

**Also:** R0075 review 003 F1 (c0184): the home rule checked a Rojo `$path` only when it was a string, so `{"optional": "../pickman/src/shared"}` mapped a path outside the home past it. A reader of a config key checks every spelling the format allows for it and reports a value of a type it does not know, instead of skipping it.

**Note (c0210 design review 001 F3):** a reader that works around a decoder keeping the last of a repeated key (Lune's `serde.decode` for JSON) must count **every** key the decoder returned, nested map names included (build names, attribute names), not only the schema's fields. It must also refuse escaped spellings: a key written `"project"` decodes to `project`, but a text count of `"project":` cannot see it. c0210's first reader counted fields only, so a repeated attribute key and a `\u`-escaped field passed. Its fix refuses any backslash (no field needs one) and counts every key of every object. The same review found the reader claiming "one project never goes to two places" while it checked only build names; a claim about files compares the files' paths in one spelling (`.` and `<dir>/..` folded). Check: for each object the format holds, maps of user-chosen names included, is a repeated key refused, and is a key spelled with an escape refused or counted?
