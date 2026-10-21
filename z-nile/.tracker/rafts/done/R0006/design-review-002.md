# Review 002: R0006 (design mode)
Inputs: main 81f9b45 plus the uncommitted prep: `tracker/rafts/R0006/{R0006-raft-browser.md,check.sh,design-review-001.md,design-refute-001.md}`, `tracker/issues/c0042/{c0042-raft-browser.md,check.sh,acceptance/*.spec.luau}`; existing `scripts/tracker/{main,store}.luau`, `scripts/tracker.sh`, `scripts/check.sh`, `scripts/lib/ac.sh`, `SETUP.md`, `.github/workflows`. Probed in the session scratchpad (outside the repo, since removed): the marked 18.0.14 tarball (sha256 matches the pin), the smoke spec's HARNESS extracted verbatim, and hand-written pages for the smoke fixture's model, each run through `node harness.js page.html "" walk` and `... "#c0006" hash`, one of them also loaded in headless Brave.
Dropped from review-001: F1, F2, F3, F4, F5, F6, F7 (each fix is in the documents and specs as the refutation says: AC6 exists, directory-only Active and Waiting-only filtering are recorded user decisions, `blockedBy` covers raftless issues (R0007/f0060), f0080 is raftless and homed, cli.spec checks every issue's `home`, `<meta charset="utf-8">` is asserted, and the F7 behaviours are specified). The findings below are new, most of them about holes in the new AC6 harness.

### F1 [high] AC6's fake DOM gives the page script every element no matter where the script sits, so a page script in `<head>` passes AC6 but crashes in every browser
Where: `acceptance/smoke.spec.luau` HARNESS (`els` is filled up front and `getElementById: i => els[i] || null`); c0042 Design, "The page" (Layout: "board-data sits before the page script", but nothing says the page script comes after `#pane`); R0006 Risks ("AC6 runs it under node against a fake DOM ... What's left for OC1 is layout and clicks")
Evidence: I built a page with the smoke fixture's model and a working page script, in two variants: (a) `board-data` and the page script at the end of `<body>`; (b) both in `<head>` right after marked, which the Layout text allows. Both print `SMOKE OK` in both modes. In headless Brave, (b) logs `Uncaught TypeError: Cannot read properties of null (reading 'addEventListener')`: when a head script runs, `#search`, `#list` and the rest haven't been parsed yet. The page is blank and no key works. (a) loads with no error. The usual fix, wrapping init in `document.addEventListener("DOMContentLoaded", …)`, *fails* AC6, because the harness never dispatches that event. So the harness can't tell a correct placement from a broken one, and the executor gets no hint which placement is required. Only OC1 catches it, and OC1 doesn't block the merge.
Fix: In the Layout bullet, say that `board-data` and the page script are the last children of `<body>`, after `#pane`. In the harness, while the page's scripts run, have `getElementById(i)` return an element only if `html.indexOf('id="' + i + '"')` comes before the running script's `match.index`, and return every element once loading is done. Alternatively, have page.spec assert that the page script's `<script>` comes after `id="pane"`. Either way, the head-placed variant fails.

### F2 [high] The Waiting start and the empty tab, which is what the user sees every time on `main`, are never exercised: a hard-coded `initialTab = "active"` passes AC1 and AC6
Where: `acceptance/model.spec.luau` "opens on Active when it has entries, otherwise on Waiting" (asserts only `"active"`); `acceptance/smoke.spec.luau` fixture (has an active R0002, and no tab is ever empty); c0042 Problem (user decision: Active is empty on `main`) and OC1 step 1
Evidence: Both fixtures contain an active raft, so the "else waiting" branch is never taken. `initialTab = "active"` as a constant in `collect` passes model.spec. A page script that ignores `M.initialTab` and starts on `"active"` passes the smoke walk: I ran that variant and got `SMOKE OK` in both modes. Neither spec ever renders an empty tab, so a page that throws on `M.tabs.active[0]` being `undefined` (for example `byId[L[0]].title`) also passes. The user's recorded decision makes this the *normal* case: on `main`, Active is always empty. With these two bugs, the page opens on an empty Active tab or crashes, and nothing but OC1 notices. cli.spec on the real tracker doesn't check it either, and during execution R0006 itself is active.
Fix: In model.spec, collect a second small tree with no `active/` rafts and assert `initialTab == "waiting"` and `tabs.active == {}`. In smoke.spec, add a mode that renders that tree and asserts: the page opens on Waiting; ← then shows the "Nothing here" row with no exception; ↓/↑ on the empty tab don't throw.

### F3 [high] AC6 names ←/→ but never presses ←, and several designed key and search behaviours can be broken without failing it
Where: `acceptance/smoke.spec.luau` walk; c0042 AC6 ("←/→ cycle tabs, ↓/↑ move the selection"), Design "Keys" and "Search"
Evidence: The walk sends only ArrowRight, ArrowDown, ArrowUp (from row 2) and Enter. I ran these variants of a working page script, and each printed `SMOKE OK`:
- ArrowLeft does nothing, although AC6 names ←.
- `/` focuses the field without `preventDefault`. In a browser, the `/` then lands in the field, so OC1 step 4's `/`, `c0041`, Enter searches for `/c0041` and turns the field red.

These aren't exercised either, and a wrong implementation of each would pass for the same reason:
- ↑ clamping at the first row;
- ↓/↑ from a pane-only view (the designed "↓ selects the first row, ↑ the last");
- arrow keys typed into the search field being ignored (the harness never sends an arrow with `target = search`);
- Esc;
- a search hit switching the *list* to the entry's tab: after `F0031` only the pane is checked, so a jump that leaves the list on Active passes.
Fix: Extend the walk:
- ArrowLeft from Active shows Done;
- ArrowUp on row 0 stays there;
- after searching `F0031`, the list shows Waiting's rows and no row is `sel`, and ArrowDown then selects R0005;
- ArrowDown with `target = search` changes nothing;
- `/` calls `preventDefault` (the fake event records it) and focuses search (the fake `focus` records it).

State in the Design that `/` calls `preventDefault`.

### F4 [medium] Once promoted, the smoke spec makes `node` a prerequisite of `scripts/check.sh --full` on every host, but SETUP.md and the Touched modules don't say so
Where: `tracker done` promotes `smoke.spec.luau` to `tests/acceptance/c0042/`, and `scripts/check.sh --full` then runs it (`lune run tests/run`); SETUP.md "Prerequisites" (no node); c0042 "Touched modules" (no SETUP.md); R0006 Risks ("preinstalled ... on this machine")
Evidence: `grep -i node SETUP.md .github/workflows/*` finds nothing. SETUP.md's prerequisites are the Xcode CLT, gh, curl and unzip, and `scripts/setup.sh` ends with `scripts/check.sh --full`. The Xcode CLT don't ship node, so on a fresh Mac set up by SETUP.md the gate fails from the day R0006 merges, in a game repo whose gate had no JS dependency. That's also the repo's documented new-host path (the "New machine: see SETUP.md" line in AGENTS.md). CI works only because ubuntu-latest happens to include node.
Fix: Add node to SETUP.md's prerequisites table (`brew install node`; preinstalled on GitHub runners), and add `SETUP.md` to Touched modules and to the Files table. Optionally, have `scripts/setup.sh` check `command -v node` with a clear message.

### F5 [medium] A waiting raft blocked only by a raftless issue has no link from anywhere: the design's reachability claim is false for it
Where: c0042 Design "Tabs" ("Blocked waiting rafts ... are reachable through their blockers' Dependents or Waiting-for links, and through search"); Usability "Findable"; model fixture R0007/f0060
Evidence: R0007 is blocked only by f0060, so it's not in `tabs.waiting`. Its blocker f0060 is an issue in the `none:waiting` pane. Issues have no dependents field, and pseudo entries have `dependents` empty (Design: "`blockedBy`, `dependsOn` and `dependents` empty"), so no pane shows a link to R0007. The only way to R0007 is typing its id. This is the next thing the real tracker will hit: f0016–f0033 are raftless and chain `depends_on` among themselves (for example f0030 `depends_on: [f0016, f0017, f0014]`). Rafting any of them before their raftless dependencies makes that raft vanish from navigation. Only a raft blocked by another *raft* is linked.
Fix: Give each No raft entry `dependents`: the sorted rafts whose `blockedBy` contains one of its issues. The pane then links R0007 from `none:waiting`. Assert `rafts["none:waiting"].dependents == {"R0007"}` in model.spec, and change the "`dependents` empty" sentence. Alternatively, correct the claim to say these rafts are reachable only by search, and get the user to accept that.

### F6 [low] Stale or inaccurate statements an executor will trip over
Where: c0042 OC1 step 4, "Affected specs", `Issue` type block
Evidence:
- OC1 step 4 says "Typing `r0040` shows R0004 in the pane (a dependent raft)". On the real tracker, R0004's members depend only on c0010 (R0003, done) and c0041 (R0005, done), so R0004 is top level and is a Waiting list row, not pane-only.
- "Affected specs" still says "the four acceptance specs"; there are five.
- The `Issue` type is written as `kind: string (= "issue")`, which isn't Luau.
Fix: In OC1, use a raft that really is blocked, or drop the parenthetical. Say "five". Write `kind: string, -- "issue"`.

Verdict: changes
