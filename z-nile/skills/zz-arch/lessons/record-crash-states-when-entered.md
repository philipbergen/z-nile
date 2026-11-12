---
title: A state a crash can leave is recorded when it is entered, never guessed from what the files look like
when: both
tags: [crash, recovery, state]
check: For each recovery state the design names ("died after storing the answer", "copied but not moved"), is it recorded explicitly, in the same write as the step that enters it, and could another sequence of events leave the same files, so that a guess from the files would take a different state for it?
---
A retry that dies between two writes leaves files; the same files can also be left by a different, healthy sequence.

**Why:** c0256 design review 002 F1: the first fix read "the retry died after storing the answer" from "`questions.md` waits and the last message is an answer", which is also what a re-run that asked again and then lost its dispatcher leaves. The new question was never recorded, the user's answer was refused as "already recorded", and the step was told its question was settled.

**How to apply:** save a marker with the write that enters the state (here the hash of the file the answer was taken from, in the same save as the answer), clear it after the step that leaves the state, ignore it when the file it names is gone or different, and build the recovery case from the marker; add the healthy sequence that leaves the same files as its own case.

**Note (c0256 review 004 F2):** an action that cannot be recorded after it happens, such as a push or another remote call, is recorded as an intent before it and checked against the remote afterwards: the intent survives a kill at any point, and the remote says whether the action landed. Ask of any "cannot be recorded" claim: was a write-ahead intent considered?
