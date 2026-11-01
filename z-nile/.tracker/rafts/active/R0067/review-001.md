# Review 001: R0067 (code mode)
Inputs: raft branch HEAD 14235979a1485fb9059601f0781d3bd6f9c62ccf against origin/main 85e17727cc22fe058c4bcc7c7f2d74a391f5d448; the landed capture `git show d7714681` (29 documents); the 27 stub commits (3d8dfe68 … 3094dbe0); R0067.md and its check.sh; c0190.md (Design item 2's list, dependency table and ownership table), its check.sh and `experiments/capture.py`; c0183's arcade block (Tracker work, Step 2 and Order); `snake/`, `invaders/`, `asteroids/`, `portal/` `.tracker/game-design.md` and `arcade/.tracker/architecture.md`.
Not run, as the brief says: `z-nile/check.sh --full` (the land's own full gate passed, per the Verification log).

What was run, and what it showed:
- `./zn check c0190`: AC1 to AC4 PASS, 4/4, exit 0.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing. `git diff --summary origin/main...HEAD` shows only `create mode 100644 z-nile/.tracker/rafts/active/R0067/spend.md`.
- The PR diff is c0190's Verification log line, c0190's spend and the raft's spend.md. Nothing else.
- The land (`git show --stat d7714681`): 29 files, all `<id>.md`. That is the 27 new issues, plus `pickman/.tracker/issues/c0188/c0188.md` and `f0187/f0187.md`, which change one line each: `depends_on`. c0188 `[f0187]` → `[f0187, f0209, c0210, c0202]` (P5, Z3, K3); f0187 `[]` → `[c0210, f0209]` (Z3, P5). Both are still `raft: ` empty and `design: draft`. No other file is touched. Each of the 27 stub commits touches only its own `<id>.md`, its `check.sh` and `z-nile/next`.
- The subject is `tracker: new` followed by all 27 ids, f0197 … f0223, written out with no range.
- `./zn capture f0197|c0210|f0213|f0223`: each names d7714681 and returns the filled document.
- `./zn audit`: 0 errors, 1 warning (orphan raft R0040, which is already on origin/main and unrelated).
- Dependencies: I checked all 27 `depends_on` lines and c0188's and f0187's by eye against item 2's table, with the keys resolved through the Verification log's map. All match. AC3 checks this too.
- Titles match the table. The three stub titles that came from slugs ("N place deploy", "Arena maps growth", "Boost golden apples crumbs") were corrected to the table's titles in both `title:` and the heading.
- Types: K1 to K4 and Z3 are chores, the rest are features.
- Scope against c0183's Step 2: every item in the list is captured with its named outcomes. That includes S1's wall generator, S2 with E6, S3 "on every platform", P4 with ARENA, 2 PLAYERS and pairing, Z3 in portal, and T3 with E7.
- The figures in the outcomes match the designs: Snake's 0.5 s shed down to 4 segments, +3 every 20 s for 6 s, 24 players to start, 10 s offer in the arena; Invaders' 5 × 11, up to 3 alien shots, extra life at 1,500; Asteroids' 4 shots, extra every 10,000, × 1.5 rocks.
- "Rest of" lines: one line per design file per owner, compared across all issues (the script below). Each file's set is the same in every issue that names it, and matches the ownership table, except for F1.
- Spend: 27 `tracker: spend <id> capture` commits on origin/main, 0.6 min each.

### F1 [low] The arcade map's "rest of" Non-goals line omits f0187, which the ownership table gives part of the arcade map
Where: the 14 arcade-owning issues' Non-goals line "The rest of `arcade/.tracker/architecture.md`: …"; c0190.md item 2, ownership table row "Arcade | Places and publishing: `LobbyPlaceId` becomes `PortalPlaceId` in pickman | f0187".
Evidence: I collected each issue's "rest of" ids plus its own id from the landed text:
`for f in $(git show --name-only --format= d7714681 | grep -v -e c0188 -e f0187); do … grep '^- The rest of \`' … done | sort | uniq -c`
For the arcade map, all 14 issues give `c0184 c0185 c0198 c0200 c0202 c0204 c0210 f0197 f0199 f0201 f0203 f0206 f0209 f0212 f0218 f0222`, with no f0187.
Nine of the 14 never name f0187 anywhere in their Non-goals (count of `f0187` between `## Non-goals` and `## Solution`): f0197, f0199, f0201, f0203, f0212, f0218, f0222, c0198, c0204 have 0; c0200, c0202, c0210, f0206 have 1; f0209 has 2.
So every arcade Problem's sentence "The rest of it belongs to other issues (c0190's ownership table), listed under Non-goals" is not literally true for the arcade map. The nearest case is f0199 (Shared travel): it owns the place-id attributes, `PortalPlaceId` included, and never names f0187 as the owner of the `LobbyPlaceId` → `PortalPlaceId` rename. Design item 2 chose this ("for the arcade's map, also c0184 and c0185"; only "the portal's line also names f0187"), so the capture is faithful to the Design. The gap is in the Design's rule, and AC4 pins it.
Critique: low, because each Problem points at c0190's ownership table, which does name f0187, and c0200 and c0210 name it outright. The tempting fix is to edit the 9 landed documents in this raft. R0067's Risks rule that out: a wrong capture is fixed by a new batched capture after the user is told, never by editing the landed text in the raft.
Consequences: a re-capture for one missing pointer costs a land and a full gate. It also changes the issues' captured text after AC4 pinned it, so AC4 would then judge a capture that is no longer the newest.
Recommendation: leave the landed text. Record it in the raft's harvest as a note on z-ticket/split-designs-name-each-owner: generated "rest of" lines must be built from the ownership table's owners of that file (issues captured earlier included), not only from the new issues' records. f0199's prep then reads f0187's ownership from c0190's table, which its Problem already points to.
Lesson: z-ticket/split-designs-name-each-owner

### F2 [low] P1 (f0205) and P3 (f0207) both state they show "FREE GAME READY"; the ownership table gives it to P3 alone
Where: f0205's Problem: it owns "the price badge's sale text", and its outcome adds `or "FREE GAME READY" when that game's free game is due (f0207 decides when)`. f0207's outcome: "flips to FREE GAME READY when it is due". c0190 item 2: the table row "The card's FREE GAME READY and countdown | P3", against the "What the outcomes need" bullet "P1 the badge and free state, A3".
Evidence: quoted from `git show d7714681:portal/.tracker/issues/f0205/f0205.md` and `…/f0207/f0207.md`. c0190's Design says both things, and the capture copies both.
Critique: the parenthesis "(f0207 decides when)" splits the work (P1 draws the badge's states, P3 computes when the free one is due), so neither prep is misled into dropping it. But two Problems name the same visible outcome. The tempting fix is to move the words out of one Problem, which would edit landed, AC4-pinned text.
Consequences: none if handled in prep.
Recommendation: no change to the capture. P1's and P3's preps (they will likely share a raft) state the split in their Designs: P1 renders the badge for the states it is given, and P3 owns the per-player due time and the flip.

### F3 [low] f0206's ownership sentence is garbled for E3
Where: f0206's Problem: `This issue owns these parts of it, as they are said there: from "Each card shows", the game's hiscores; **Unknowns** E3 is in \`arcade/.tracker/architecture.md\`.`
Evidence: the other issues that own a part of the arcade map say it as "in `arcade/.tracker/architecture.md`, **Unknowns** E<n>" (f0212, f0218, f0222). f0206's reads as a statement of where E3 is, not that f0206 owns it. The outcome bullet ("within Roblox's DataStore budget (E3 …)") and its "rest of arcade" Non-goals line make the ownership clear.
Critique: clarity only. The text is pinned by AC4 and landed.
Recommendation: no change. Record it in the harvest as part of F1's note: the pointer template for a second file should read the same in every issue.

### F4 [low] The quote of the user in all 27 Problems is longer than any record before c0190's prep, and its source is not written down
Where: every new Problem's first paragraph, which runs from "I want you to design a full fun playable game …" through "… split into two groups that move toward either player". Compare c0183's Problem, which quotes the same message only up to "highscores shoudl show how many revives were used."
Evidence: `git log --all --oneline -S"snakes can even be n-player"` gives d7714681 and 0fbf5b02 (c0190's prep) only, so no earlier commit holds those words. `./zn capture c0183` is a one-line stub.
Critique: the extra text matches c0183's recorded decisions ("the 2-player 'asteroids' design they described (aliens from the side, barriers)"), N-player Snake and the wall maps, and it carries the user's own typos. So it is almost certainly the user's real message. But the 27 captured scopes rest on it, and nothing in the repository says where it was copied from. Six design rounds read it without asking.
Consequences: none for this raft.
Recommendation: the lead adds one sentence to the Verification log saying where the full quote was taken from (the user's 2026-10-31 message, as given to c0190's prep). If the lead can't say, the lead asks the user to confirm it. Do not edit the landed text.

Verdict: approve
