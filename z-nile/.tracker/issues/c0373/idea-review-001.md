# Idea review 001

## Findings

- F1: The first Solution bullet doesn't define clearly which changes cause a publish, and it disagrees with the second bullet. The Beta places are built only from `pickman/default.project.json`, `pickman/lobby.project.json`, `pickman/src/` (the lobby is `pickman/src/lobby`, not the portal) and `arcade/src/`. "A game home's source or project files" could also mean `snake/`, `invaders/`, `asteroids/` or `portal/`, so nobody can say whether a PR that changes only `snake/src` publishes. Also, `pickman/scripts/deploy-beta.luau` requires `@znile/lib/sh` and needs the tools from `z-nile/setup.sh --tools`. So a PR that changes only `z-nile/lib/sh` must publish under bullet 1 ("what it requires") and must not publish under bullet 2 ("z-nile tooling").

## Verdict

revise
