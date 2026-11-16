---
title: A text that promises a command states the positive condition and the safe form, and its cases run on every supported tool version
when: design
tags: [docs, guards, config, versions]
check: Which configuration keys, defaults and installed versions of the tool can make the promised command do something the guard refuses, and did the case that pins the command set those keys on its own command line and run on every version SETUP.md's install paths provide (at least the oldest on hand)?
---
A rule text that promises a capability ("a check can fetch whether or not anything is new") breaks under whatever the tool lets a user change, so a list of exceptions is never complete.

**Why:** c0122's design reviews found four exceptions in turn: prune (001 F3), tag following (002 F2), `fetch.pruneTags` (003 F1) and git 2.50.1's per-ref transactions (004 F1). Each round added one more exception to the list.

**How to apply:** state the guard's positive condition and one safe command instead. Pin that command's case with every relevant setting on, set on the command line (`-c` outranks global config and names nothing a gate scan bans). Add a real-tool case for each class the guard refuses, and run the cases on the oldest version on hand (`PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH` selects the Command Line Tools' git on this machine). Take the key list from the tool's own listing (`git help --config | grep -E '^(fetch|remote|transfer)\.'`) and say which keys were run.
