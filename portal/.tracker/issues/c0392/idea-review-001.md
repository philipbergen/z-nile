# Idea review 001

## Findings

- F1: The Solution removes more than f0209 breaks. Its first sentence says the deploy cases will "pin only" a short list. That list leaves out checks on Pickman's game place that pass both before and after f0209: the game's `Server` child, the missing `GamePlaceId` on the game, and the `version=1333` output line (`lobby.spec.luau:118-123,134`). Its second sentence also drops the `*PlaceId` attributes on the start place. c0210's design says every place gets those, the portal included, so that check would still pass after f0209. The Problem only justifies removing checks that turn red: the lobby's structure, its `GamePlaceId`, the missing `LobbyPlaceId` on it, `lobby_version`, the lobby project file and the `--place Portal` lobby scripts. c0210's own design asks for exactly that narrower cut: "keep the Pickman game case … drop the lobby-at-start and `--place Portal` lobby-scripts pins … and drops nothing else" (`prep-n-place-deploy:portal/.tracker/issues/c0210/c0210.md:157`).

## Verdict

revise
