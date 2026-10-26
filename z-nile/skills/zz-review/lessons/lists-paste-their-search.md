---
title: A finding that lists N places pastes the search that found them
when: both
tags: [findings, coverage]
check: Is this list of places the output of a search I can rerun, and is that search in the finding?
---
A finding that names "the N places that do X" from memory, or from the files the reviewer happened to read, misses the next one, and the fix, the capture or the next round starts from the short list. Search the whole corpus for the mechanism, and paste the search with its result, so the author and the next reviewer can rerun it.

**Why:** c0115 design review 011 F4 listed four finished `.claude` scans that pass vacuously from `z-nile/`; review 012 F3 found a fifth (c0069 `check.sh:41`), which the capture (c0137) had already copied the short list from.

**How to apply:** for every finding that enumerates places, run one search over every file the mechanism could be in (`git grep -nE '<the form>' -- '<the paths>'`), paste the command and its hits, and say what each hit is or why it's excluded. Put the same search in a capture made from the finding.

c0153 design review 001 F2: the author's own Regression guard said "no other spec uses the exact JSON compare" from a search for `serde.decode("json"` that only matched the two-line form; four more specs put `serde.encode` inline. An author's guard that claims "no other place" is a list too: paste its search, and make the pattern cover every spelling of the mechanism.
