---
id: R0080
type: chore
title: Beta deploy
single: false
issues: [c0140, c0030]
design: draft
created: 2026-09-30
---

# R0080: Beta deploy

## Theme
Roadmap raft **b**: a ready PR goes live on the private Pickman Beta experience (last one wins), plus engine smoke tests through Open Cloud. It gets later rafts in front of real players, and it's infrastructure, so it's a chore. `tracker/game-design.md` says every PR that becomes ready is published to Beta; production publishing is decided later.

## Prep experiment (2026-09-30): PASS, after one correction
Permitted by the user: one test publish to Pickman (Beta) and one trivial Luau execution, through a one-off workflow on a throwaway branch (`experiment/open-cloud-probe`, deleted afterwards).
- **Attempt 1 (run 36790710861)**: `POST .../universes/v1/universes/$U/places/$P/versions` was refused by Roblox's edge (`403 {"code":9009,"message":"WAF Blocked Request"}`). Nothing was published. The cause was **my malformed URL** (a doubled `universes/`), not the runner or the tool. A User-Agent change was (rightly) not tried.
- **The working request**, copied from `../karma`'s `make beta` (the user's pointer): `curl -sS -L -X POST "https://apis.roblox.com/universes/v1/$U/places/$P/versions?versionType=Published" -H "x-api-key: $KEY" -H "Content-Type: application/octet-stream" --data-binary @place.rbxl`.
- **Attempt 2 (run 36793719983, GitHub-hosted ubuntu-latest, Rojo 7.7.0 from its release zip)**: `rojo build` made a 17 KB .rbxl; the publish returned **HTTP 200 `{"versionNumber":5}` in 1 s**; then `POST https://apis.roblox.com/cloud/v2/universes/$U/places/$P/versions/5/luau-execution-session-tasks` with `{"script": "..."}` returned 200 `state: PROCESSING`; polling `GET .../cloud/v2/<path>` reached `COMPLETE` after about 4 s, `output.results[0]` = `ok 2 sss=Server players=0`, logs empty. So a published Rojo build's `ServerScriptService.Server` exists and Luau runs in it.
- **Facts for the designs**: the API key works with both the publish and the execution scopes; a publish replaces what Beta testers play (Beta is now at version 5, a bare build of main at 2973d6c); karma retries HTTP 409 ("Roblox busy") up to 5 times 60 s apart and treats missing config as a green skip; it runs its tests first (`needs: luau-test`) then publishes.

## Whole-raft design
<!-- Module map, the interfaces between member issues, data flow. Diagram if it helps.
     Every issue design must agree with this. Include any tracker/architecture.md changes. -->

## Order & dependencies
<!-- Execution order of member issues and why. -->

## Experiments phase
<!-- All unknowns across the raft, run FIRST. For each: question, command, result (if run in prep),
     fallback. If an experiment fails without a fallback: stop and escalate. -->

## Exit criteria
<!-- Exact, machine-checkable goal state. Implemented by this raft's check.sh (RCn labels).
     "Done" == `scripts/tracker.sh done R0080` succeeds. -->

## Risks & rollback

## Addressed during execution
<!-- Emergent issues created and fixed in this PR (id, why it could not be postponed). -->
