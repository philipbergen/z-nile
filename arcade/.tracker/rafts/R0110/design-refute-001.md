# R0110 design-refute-001

- F1: fixed: the Order section is f0201 then f0199, each id once, and the layers follow that section. Whole-raft design composes PaidPlay's Features section first, then Travel's heading, and lists the one departure: the deps comment becomes exactly `# PaidPlay and Travel are leaves`. RC1 compares that whole deps block and both headings after `## Features`. Consequences: `./zn workstreams` still prints f0199 in wave 1; execution follows `./zn stack`.
- F2: fixed: the Theme copies f0201.md lines 42-45 verbatim. Consequences: the quoted rulings are the member's text, including the ones it copied from f0145's prep.
- F3: fixed: Cross-raft waits lists the c746326c properties, the stop rule that reads the prep tip while that branch exists, and the note for f0145's prep lead in this raft and the pull request. Consequences: today's draft on origin/main is not a false stop, and f0145.md is not edited.
- F4: fixed: the patch count is six files under arcade/src and one unit spec, and the acceptance sets are marked reasoned, not run, with the Places require and the two experiment results named. Consequences: none.
- F5: fixed: c0367 is listed with the Gate and selector judgment, and the git grep that found it is pasted. Consequences: the other hits are listed and not judged beyond the ones already written.
