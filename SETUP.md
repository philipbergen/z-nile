# Setting up a host

Everything here is automated by `scripts/setup.sh`, which is idempotent. This file explains what the script does and how to fix it when it fails.

```bash
git clone git@github.com:philipbergen/pickman.git && cd pickman
scripts/setup.sh
```

## Prerequisites (manual, one time)
| need | macOS | Linux |
|---|---|---|
| git + a C toolchain | `xcode-select --install`, then **`sudo xcodebuild -license accept`** (without this, git and cargo fail with "You have not agreed to the Xcode license") | distro packages |
| GitHub CLI | `brew install gh` | see cli.github.com |
| GitHub auth | `gh auth login` (the tracker opens draft PRs with `gh`) | same |
| curl, unzip | preinstalled | distro packages |

## What `scripts/setup.sh` does
1. **Rokit** (the toolchain manager, v1.2.0): downloads the prebuilt release asset with `gh release download -R rojo-rbx/rokit`, then runs `rokit self-install`.
   - This installs to `~/.rokit/bin` and adds `. "$HOME/.rokit/env"` to your shell profile.
   - Compiling it with `cargo install rokit` fails at the moment because of a yanked dependency, so the script uses the prebuilt binary.
2. **Pinned tools**: `rokit install` installs what's listed in `rokit.toml`: rojo, selene, stylua, luau-lsp and lune.
   - To upgrade a tool: `rokit add --force <owner/tool>`, then commit `rokit.toml` as a chore issue.
3. **Lune type definitions**: `lune setup` writes them to `~/.lune/.typedefs/<version>/`.
   - `.luaurc` refers to them through the `lune` alias (`~/.lune/.typedefs/<version>/`). The version in that alias must match `rokit.toml`.
4. **Gate**: runs `scripts/check.sh --full`.
   - The first run downloads the Roblox type definitions for luau-lsp to `.cache/globalTypes.d.luau`. This is gitignored and fetched again if missing.

## Optional: Roblox Studio (needed for Observed criteria and playtesting)
1. Install Roblox Studio.
2. Install the Rojo plugin with `rojo plugin install`, or from the Studio plugin marketplace.
3. `rojo serve`, then Connect in Studio. You should see `ReplicatedStorage.Shared`, `ServerScriptService.Server` and `StarterPlayer.StarterPlayerScripts.Client`. Play prints `[pickman] server started` and `[pickman] client started`.

## Agents on this host
- **Claude Code**: `CLAUDE.md` imports `AGENTS.md`. The hooks in `.claude/settings.json` format and lint each `.luau` edit, and gate the Stop event.
- **Other agents** (Grok, Codex, …): read `AGENTS.md`. For execution, give them the prompt from `scripts/tracker.sh prompt <id>`, which is self-contained.

## CI
`.github/workflows/check.yml` runs `scripts/check.sh --full` on main and on PRs that are **not drafts**. Draft pushes cost no CI.

## Troubleshooting
| symptom | fix |
|---|---|
| `lune: command not found` | open a new shell, or `export PATH="$HOME/.rokit/bin:$PATH"` |
| luau-lsp can't resolve `@lune/...` | run `lune setup`, and check that the `lune` alias version in `.luaurc` matches `rokit.toml` |
| `sourcemap parsing failed` | a Rojo `$path` directory has no `.luau` files. Every root needs at least one |
| `tracker.sh start` fails on `gh pr create` | `gh auth status`; and there must be an `origin` remote |
