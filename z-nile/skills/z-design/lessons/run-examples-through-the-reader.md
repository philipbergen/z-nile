---
title: Every example input in a design goes through the reader the design specifies
when: design
tags: [examples, parsers, consistency]
check: Has each example file, line or argument in the Design been fed to the parser or rule the Design names, and does it get the result the text around it claims?
---
An example written to explain a format can contradict the format's own rules, and then the rule is wrong, or the example is, or a whole class of real inputs the example stood for can't be expressed.

**Why:** c0165 design review 001 F5. The `inputs.tsv` example named a path under `pickman/.tracker/`, which the design's own parser refused. That exposed a class of graph misses (specs that read tracker files as text, 138 spec files mention them) that could never be declared or learned.

**How to apply:** for each example, run it (or reason it line by line) through the specified reader, and make it an acceptance case: the parser accepts the example, and refuses each near-miss the rules name.
