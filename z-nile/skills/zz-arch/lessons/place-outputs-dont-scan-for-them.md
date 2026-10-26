---
title: Place an agent's output yourself; don't find it by scanning a shared folder for new names
when: both
tags: [dispatch, outputs, concurrency, numbering]
check: When an agent's output is found by scanning a shared folder for new names, can a concurrent run, a retry or a fallthrough add a matching name, and what do "none" and "two" mean? Who numbers the file? Would the runner placing a file the agent wrote in its own state folder answer all three?
---
Scanning a folder for "the new file" works for one writer and one attempt. With two runs in one folder, a retry or a fallthrough whose first attempt wrote before failing, the scan takes another run's file, counts two, or accepts none as success; and the agent numbering its own file collides with the others.

**Why:** c0117 design reviews 006 to 008 found three holes in a row in how a dispatched review's output was landed: the line, the lost file, then the count and the key. The dispatcher took any new `stream-review-*` file in the raft's folder, so a reviewer that wrote nothing still got `ok`, another issue's file counted, and a fallthrough left two rounds.

**How to apply:** have the agent write to a fixed name in its own state folder; the runner moves it into place, numbering it from the target folder by the item's own prefix. No file after a step that spent is a failure (its cost still recorded); a failed attempt's file is moved aside before the next attempt.

Replace it everywhere (c0117 design review 009 F1): when a mechanism is retired for one caller because it was found broken, list every other caller of it and replace it there too, or write why that caller can't hit the holes. c0117 moved stream reviews off the folder scan and kept it for design, raft and code reviews, which a quota fallthrough and a silent reviewer broke the same way.
