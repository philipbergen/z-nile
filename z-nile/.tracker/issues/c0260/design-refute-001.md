# Refute 001: c0260

- F1: fixed: the dispatched capture's confirmation is unattended and z-design shows the user the idea and every `ask:` line and replaces it with theirs; the audit fails a designed issue still unattended; consequences: `capturecheck` ties `unattended` to a `None:` interview and a `user` confirmation to no open `ask:`, z-design's text and the Rules rows change with it. The agent-finding exemption (no user words) is put to the user as an open question in the Design and the report, not decided here.
- F2: fixed: step 6 allows the interactive Opus subagent form and its spend row (`--note idea-review-NNN`); zz-review's Output file says the subagent writes the file itself; consequences: a second `capture` spend row, described in zz-rules; the 7200000 ms timeout stays the dispatched form's (the existing Headless text assumes it too).
- F3: fixed: fenced blocks for the verbatim ask and multi-line answers, parsed by `capturecheck`; consequences: unclosed fence error, template in the skill uses a four-backtick outer fence, Part/Interview rules unchanged, specs added.
- F4: fixed: optional `## Part` section; consequences: section list rule, an empty Part refused, specs added.
- F5: fixed: `unattended` needs `None:`; `user` allows no open `ask:`; one rule in z-design and z-ticket (z-design asks every `ask:` line and rewrites it `fixed: asked as Qn`); consequences: the refute grammar already allowed `fixed: …`.
- F6: fixed: `captureScope` refuses M of a landed `idea-review-NNN.md` and any change to the Verbatim ask, Part or an existing question (`capturecheck.appendOnly`); deletion stays refused; consequences: z-design edits the ask in the prep PR (not a land), which this guard does not touch.
- F7: fixed: refusal text in `main.luau`, zz-rules land, direct-push and spend sentences, and a skills-restated case; the lesson text is left (a lesson records what happened).
- F8: fixed: names starting with `.` are skipped by the audit; consequences: a tracked dotfile in `capture/` is still refused by `land`'s name test.
- F9: fixed: capture files are refused for an issue whose base status is not `new-…`; consequences: the message tells the author to tell the user; the issue document edit path is unchanged.
- F10: fixed: `REVIEW_MODES.idea.skills` and the prompt's lesson command; consequences: none.
- F11: fixed: E5 is a required Phase 1 experiment with a pass/fail question and a fallback; it cannot run in prep on this machine (no agent credential or watermark), said so.
- F12: fixed: both promoted cases assert membership (`idea` among the modes), not the list.
- F13: fixed: rows added for every rule; the no-op assertion replaced; consequences: none.
- F14: fixed: "at most three rounds the author starts; a change asked at step 7 gets one more".
