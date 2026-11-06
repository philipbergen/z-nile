---
title: A fake of a CLI prints what the real CLI prints for the same call
when: build
tags: [fakes, gh]
check: If I delete the `-q`/`--jq`/`--format` argument from the call, does a spec go red?
---
A fake that answers a filtered call (`gh … -q .field`) with the bare value passes for any call, including the one that would fail against the real tool.

**Why:** R0052 code review 009 F1: the fake gh answered `pr view <n> --json mergeCommit` with a bare sha whatever the other arguments were; the dispatcher's call without `-q` would have printed JSON on the real gh and stopped every unattended merge, and no spec noticed.

**How to apply:** make the fake answer only the exact call the code makes, with the real tool's output shape (decode the JSON in the code, not with `-q`), and run the mutant that drops or alters one argument.
