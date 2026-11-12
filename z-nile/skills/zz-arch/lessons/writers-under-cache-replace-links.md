---
title: An unjailed writer under .cache replaces links, and refuses a folder or entry that is one
when: both
tags: [cache, links, replacing-writes, dispatcher]
check: For each file an unjailed process (the dispatcher, the gate) writes, moves or names into a folder a step or spec can write, is it written with sh.writeReplacing (a fresh exclusive temporary file, renamed), and is every name it picks chosen by a test that sees links (readlink), every move a rename, and are the folder and every entry it reads or moves checked to be regular files and folders rather than links, with a case that plants a link at the final name, at the folder and at the file it copies?
---
`.cache` is writable by the thing the process supervises, so a link planted there is followed by a plain `writeFile` or `move` and lands wherever the user can write, a tracked file of the main checkout included.

**Why:** c0256 design review 001 F4: the prototype wrote the user's answer with `fs.writeFile` to a predictable dot name; a step planted a link there and the retry overwrote a tracked issue document. c0077 had made `sh.writeReplacing` the rule for state.json and the markers; the new writer did not use it.

**How to apply:** write with `sh.writeReplacing`; before reading a folder, ask `readlink` for it and for each entry (fs.isFile and fs.isDir follow links); refuse with the path named; cover the final name, the folder and the source file in the spec.
