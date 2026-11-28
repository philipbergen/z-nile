# Idea review 001

## Findings

- F1: Graduating the restated-rules lesson is not supported by the Problem and is not part of the smallest solution. The lesson (`z-design/restated-rules-move-together`, 410 sources) covers every restated rule: AGENTS.md, raft documents, promoted specs, `check.sh` comments and each project's `architecture.md`. Its 71 lines never mention the Headless paragraph or the Lessons section, and AGENTS.md will still restate the Lessons rule after this change. Under c0455, graduation deletes the lesson file, so the most-cited lesson would be retired while its rule still applies everywhere outside these two paragraphs.
- F2: The Solution does not say which skills owe a Headless pointer, so "missing its pointer" cannot be found true or false for most skills. Only 4 of the 26 non-alias skills hold a Headless section today. Read literally, "every other non-alias skill has a one-line pointer" either adds new Headless text to 22 skills that never run as a dispatch step, or leaves the check undecidable for them (for example `pickman-arch`).
- F3: Problem sentence 1 is false as worded. Of the 28 registered skills, the aliases `z-run` and `z-ticket` carry no Lessons paragraph, and the promoted spec (`c0111/skill-docs.spec.luau`) already skips them. "In every skill" in Problem sentence 2 has the same flaw, and the Solution's own "non-alias" carve-out contradicts both.

## Verdict

revise
