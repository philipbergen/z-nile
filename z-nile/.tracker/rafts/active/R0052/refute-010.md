# Refute 010: R0052 (answers to review-010)

- F1: fixed: main merged in (AGENTS.md keeps both texts: the results db and the dispatcher's run state with the headless sentence); `z-nile/tests/inputs.tsv` declares `.models.toml` for dispatch-texts and c0117's models spec and `AGENTS.md` for c0117's docs spec, so the selector runs them after a change to those files. The gate and `./zn check c0117` rerun on the merged tree.
- F2: fixed: `afterMerge` takes the item id, so every stop prints `./zn dispatch retry <id>` with the real id (the parent-unreadable stop names the commands too); a merge-check stop has its own text in `dispatch.next` (no "did not make"). #96 and #97 assert the output names `retry c0096`, and the held rerun's text. consequences: none (messages only).
- F3: fixed: the two new lessons are deleted; their rules are notes in `zz-test/stand-ins-answer-only-named-arguments` and `zz-rules/audit-what-new-refuses`; the harvest lines point there.
