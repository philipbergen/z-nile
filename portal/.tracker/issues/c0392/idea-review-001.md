# Idea review 001

## Findings

- F1: The second non-goal's reason is false today. It says f0209's own acceptance specs pin "that the start place is published second to its own id" and the `*PlaceId` attributes on it. But f0209 is `design: draft`, and its `check.sh` has no `check` lines, so no f0209 spec exists to pin anything, and f0209 has not committed to writing one. The `lobby-start.spec.luau` this chore removes is the only spec that checks those things end to end with the real manifest: `seen[2].path` is `/places/222/versions`, and on the start place `PortalPlaceId` is 222 and `PickmanPlaceId` is 333. `pickman.spec.luau` only checks `seen[1]`. After this chore, only c0210's AC3 still covers them (publish order, over a fixture experience) and AC8 (attributes on real builds). So the reason should point to AC3 and AC8, or f0209's design must be required to add the pin. As written, the reason depends on work nobody has agreed to do.

## Verdict

revise
