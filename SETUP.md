# Setting up a host

Everything here is automated by `z-nile/setup.sh`, which is idempotent. This file explains what the script does and how to fix it when it fails.

```bash
git clone git@github.com:philipbergen/pickman.git && cd pickman
z-nile/setup.sh
```

## Prerequisites (manual, one time)
| need | macOS | Linux |
|---|---|---|
| git + a C toolchain | `xcode-select --install`, then **`sudo xcodebuild -license accept`** (without this, git and cargo fail with "You have not agreed to the Xcode license") | distro packages |
| GitHub CLI | `brew install gh` | see cli.github.com |
| GitHub auth | `gh auth login` (the tracker opens draft PRs with `gh`) | same |
| curl, unzip | preinstalled | distro packages |
| Node.js (`node`) | `brew install node` | distro packages; preinstalled on GitHub runners. The full gate needs it: the raft board's page script is tested under node (`z-nile/tests/acceptance/c0042/smoke.spec.luau`) |

## What `z-nile/setup.sh` does
1. **Rokit** (the toolchain manager, v1.2.0): downloads the prebuilt release asset with `gh release download -R rojo-rbx/rokit`, then runs `rokit self-install`.
   - This installs to `~/.rokit/bin` and adds `. "$HOME/.rokit/env"` to your shell profile.
   - Compiling it with `cargo install rokit` fails at the moment because of a yanked dependency, so the script uses the prebuilt binary.
2. **Pinned tools**: `rokit install` installs what's listed in `rokit.toml`: rojo, selene, stylua, luau-lsp and lune.
   - To upgrade a tool: `rokit add --force <owner/tool>`, then commit `rokit.toml` as a chore issue.
3. **Lune type definitions**: `lune setup` writes them to `~/.lune/.typedefs/<version>/`.
   - `.luaurc` refers to them through the `lune` alias (`~/.lune/.typedefs/<version>/`). The version in that alias must match `rokit.toml`.
4. **Gate**: runs `z-nile/check.sh --full`.
   - The first run downloads the Roblox type definitions for luau-lsp to `.cache/globalTypes.d.luau`. This is gitignored and fetched again if missing.

## Optional: Roblox Studio (needed for Observed criteria and playtesting)
1. Install Roblox Studio.
2. Install the Rojo plugin with `rojo plugin install`, or from the Studio plugin marketplace.
3. In `pickman/` (the game's home: its Rojo projects are there), `rojo serve`, then Connect in Studio. You should see `ReplicatedStorage.Shared`, `ServerScriptService.Server` and `StarterPlayer.StarterPlayerScripts.Client`. Play prints `[pickman] server started` and `[pickman] client started`.
4. The lobby place: in `pickman/`, `rojo serve lobby.project.json`, then Connect and Play: a black screen titled HISCORES with an UNAVAILABLE button, and `[pickman] lobby server started` and `[pickman] lobby client started`. To turn the button on, set the attribute `GamePlaceId` on `ServerScriptService` to the id of the game place (Studio refuses the teleport itself; it works in a published session).

## Agents on this host
- **Claude Code**: `CLAUDE.md` imports `AGENTS.md`. The hooks in `.claude/settings.json` format and lint each `.luau` edit, and gate the Stop event.
- **Other agents** (Grok, Codex, …): read `AGENTS.md`. For execution, give them the prompt of a readied raft, `./zn prompt <R-id>` (`/z-ready` writes it), which is self-contained.
- **Worktrees**: every change is made in a worktree under `.worktree/` (gitignored), never in the main checkout, which stays on `main`. Start Claude in the main checkout and run `/z-run R0010`, which enters the raft's worktree; every job starts in a worktree directory inside the repo, never outside it. The one exception is Merging's final check and `lune run scripts/cicd` in that clone, a clone outside the repo that is not a worktree. After a PR merges, the agent removes its worktree; `./zn worktree-prune`, run from the main checkout, removes the worktrees of rafts that are done on `main`.

## CI
Verification is local. `z-nile/check.sh --full` runs every project's gate on the machine that lands or merges (`./zn land`, `./zn done`, and zz-rules Merging). GitHub Actions does not run it, and a merge does not wait for an Actions result. Specs run from a project's home (`cd pickman && lune run tests/run`, `cd z-nile && lune run tests/run`), never from the root.

## Troubleshooting
| symptom | fix |
|---|---|
| `lune: command not found` | open a new shell, or `export PATH="$HOME/.rokit/bin:$PATH"` |
| luau-lsp can't resolve `@lune/...` | run `lune setup`, and check that the `lune` alias version in `.luaurc` matches `rokit.toml` |
| `sourcemap parsing failed` | a Rojo `$path` directory has no `.luau` files. Every root needs at least one |
| `./zn start` fails on `gh pr create` | `gh auth status`. A non-GitHub `origin` skips the draft PR, and with no `origin` the push is skipped too |
| lifecycle specs fail with "No such file or directory", or git reports missing objects | the checkout is in a cloud-synced folder (iCloud Drive, Dropbox, OneDrive): move it to a plain directory such as ~/code/pickman |

## Beta publishing (Pickman Beta)
`.github/workflows/deploy.yml` is the only workflow. It publishes a pull request that is ready for review from this repo to the private **Pickman (Beta)** experience by running `lune run scripts/deploy-beta` from `pickman/`. A push to `main` and a manual dispatch start the workflow and skip the job. It does not run the gate or the runtime tests. A pull-request comment names the published version and commit.
- **Repo secret** `ROBLOX_API_KEY`: an Open Cloud key scoped to that experience, with `universe-places` write and, for the runtime tests, `luau-execution-sessions` read and write, plus `datastore.control:create` and data-store entry read, create, update and delete for the reservation. The live publish's copy is a GitHub Actions secret. The merging machine keeps its own in `~/.config/pickman/cicd.toml`, mode `600`, outside the repo.
- **Repo variables** `ROBLOX_BETA_UNIVERSE_ID` and `ROBLOX_BETA_PLACE_ID`: plain digits. `ROBLOX_BETA_PLACE_ID` is the experience's start place.
- **Two places** (c0064): the repo variable `ROBLOX_BETA_GAME_PLACE_ID` is the id of the game place. With it set, the deploy publishes `default.project.json` (the game) to it and `lobby.project.json` (the lobby) to `ROBLOX_BETA_PLACE_ID`, with the game place's id written into the lobby's `GamePlaceId` (in a copy of the project built outside the checkout; the checked-in value stays 0). Both are built before either is published. Without it, the deploy warns and publishes the game to `ROBLOX_BETA_PLACE_ID` as before, and the lobby is not live.
- **Setting up the game place** (once, by the owner of the experience; nothing in the repo can do it):
  1. Creator Dashboard, Pickman (Beta), Places: create a new place (for example "Pickman Game") and copy its place id (the digits in its URL). Leave the existing place as the start place: it becomes the lobby.
  2. GitHub, Settings, Secrets and variables, Actions, Variables: add the repository variable `ROBLOX_BETA_GAME_PLACE_ID` with that id.
  3. Check the key: `ROBLOX_API_KEY` must cover the new place too (`universe-places` write and `luau-execution-sessions` read and write for the experience, not for one place). A key limited to the old place fails the game publish with HTTP 403.
  4. A pull request that is ready for review publishes both places. The job does not run the runtime suites. Its log names both versions.
- If any of the three is missing the job skips with a warning instead of failing. Forks never get the secret, and the secret is only in the environment of the steps that need it.
- Publishes happen one at a time (`beta-deploy`, and a running publish is not cancelled). The comment names the pull request's commit.
- The job has a 20-minute timeout, because it holds the shared `beta-deploy` lock.
- The job installs only the tools (`z-nile/setup.sh --tools`).
- By hand: export the three settings (and `ROBLOX_BETA_GAME_PLACE_ID` for both places) and run `lune run scripts/deploy-beta` in `pickman/` (the job runs its steps there too). That publishes to Beta.
- A merge runs `lune run scripts/cicd` from `pickman/`. It reads `~/.config/pickman/cicd.toml`, reserves the CICD places, publishes them, and runs both runtime suites. A missing file or a failed suite stops the merge. The command is not part of the gate. By hand, after a version exists: `lune run scripts/runtime-test -- <version>` for the game place (`tests/runtime/`), and `lune run scripts/runtime-test -- --lobby <lobby version>` for the lobby (`tests/runtime/lobby`). They skip with a warning when the settings are missing. The comment's version is the game place's.
