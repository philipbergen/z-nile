# Design refute 006: c0190

- F1: fixed: S3 depends on Z3 (the manifest that publishes its place); I3 reaches Z3 through P5 and T3 through I3, so every view issue waits for it; consequences: S3 now follows P2 and P4 (Z3's own dependencies), which follow A1 and A3; mutant "S3 without Z3" added.
- F2: fixed: I3's E5 outcome now says its raft's experiments phase first asks the user to create the Invaders place and set `ROBLOX_BETA_INVADERS_PLACE_ID`, so the manifest publishes it before E5 runs; consequences: the step is an experiment prerequisite, not an Observed step after the work.
- F3: decided with the user (2026-11-01): "Keep the order": I3 and T3 wait on Pickman's paid play (K3, f0145, f0186) through P5; the Design records it; consequences: the rules issues still start right after c0184.
- F4: decided with the user (2026-11-01): "When it is playable": a game's place is first published to Beta (the private test experience) at its view issue, before its boards, revives and game-over return; the Design records it.
- F5: fixed: the AC3 prose (Design item 3 and the criterion) says c0188 depends on P5, Z3 and K3 and f0187 on Z3 and P5; the prototype's mutant run is redone on prototype 7 with the current script (E8).
- F6: fixed: K3 depends on A2, as every arrival does under the Design's rule.
- F7: fixed: f0187 gains P5 (`EXTRA`; AC3 reads it at the capture), so pickman reads `PortalPlaceId` only once the portal is the start place; the handover text and the order table say so; mutant "f0187 without P5" added.
