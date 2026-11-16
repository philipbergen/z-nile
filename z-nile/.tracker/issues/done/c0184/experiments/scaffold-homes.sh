#!/usr/bin/env bash
# c0184 prototype: writes the five arcade homes (everything but their skills, which are in skills/ beside this file).
#   bash scaffold-homes.sh <checkout>
# Run on a checkout that has c0183's registry and roots. Each home gets: check.sh, .luaurc, stylua.toml and selene.toml
# (links to the root's), default.project.json, src/, and tests/ (the runner, t and renamed, and the two meta specs); and
# an empty deps block appended to its root's architecture.md. Also pickman's tests/meta/home.spec.luau (the rule's
# wrapper). The two files in lib/ are copied to z-nile/tests/lib/ by hand (Implementation steps).
set -euo pipefail
cd "$1"

home() { # home <name> <kind: game|lib>
  local h=$1 kind=$2
  mkdir -p "$h/tests/lib" "$h/tests/meta" "$h/src/shared/Logic" "$h/src/server"
  cat >"$h/check.sh" <<EOT
#!/usr/bin/env bash
# $h's gate (c0184): the repository's gate for this project alone. See z-nile/skills/zz-test/SKILL.md.
#   $h/check.sh [--full|--affected] [--base REF]
exec bash "\$(dirname "\$0")/../z-nile/check.sh" --project $h "\$@"
EOT
  chmod +x "$h/check.sh"
  cat >"$h/.luaurc" <<'EOT'
{
  "languageMode": "strict",
  "aliases": {
    "logic": "./src/shared/Logic",
    "shared": "./src/shared",
    "tests": "./tests",
    "znile": "../z-nile"
  }
}
EOT
  ln -sf ../stylua.toml "$h/stylua.toml"
  ln -sf ../selene.toml "$h/selene.toml"
  : >"$h/src/shared/Logic/.gitkeep"
  cat >"$h/tests/run.luau" <<EOT
--!strict
-- $h's spec runner (c0184): the repository's one runner, z-nile/tests/run.luau, run from this project's home, so
-- its specs, their fixtures ($h/.cache) and the paths they name are $h's. From $h/:
--   lune run tests/run [-- <spec files relative to $h/>]
return require("../../z-nile/tests/run")
EOT
  cat >"$h/tests/lib/t.luau" <<'EOT'
--!strict
-- The assertions every spec uses are the shared runner's (z-nile/tests/lib/t.luau); this home's specs reach them
-- as @tests/lib/t, which this home's .luaurc points at its own tests/ (c0184).
local t = require("../../../z-nile/tests/lib/t")

export type Case = t.Case
export type Spec = t.Spec

return t
EOT
  cat >"$h/tests/lib/renamed.luau" <<'EOT'
--!strict
-- The compaction-map lookup is the shared harness's (z-nile/tests/lib/renamed.luau); this home's specs reach it as
-- @tests/lib/renamed, which this home's .luaurc points at its own tests/ (c0184).
return require("../../../z-nile/tests/lib/renamed")
EOT
  cat >"$h/tests/meta/fence.spec.luau" <<EOT
--!strict
-- $h's specs run from $h/, jailed to $h/.cache (c0184): the repository-fence spec, run here too, proves in $h's own
-- gate that this run is guarded and can write nothing outside its .cache.
return require("../../../z-nile/tests/tooling/repo-fence.spec")
EOT
  cat >"$h/tests/meta/home.spec.luau" <<EOT
--!strict
-- The home rule for $h (c0184): what every project with code has in its home (z-nile/README.md, A project's home), run
-- from this folder, so a change to the home selects it.
return require("../../../z-nile/tests/lib/homespec")
EOT
  cat >"$h/tests/meta/architecture.spec.luau" <<EOT
--!strict
-- The structural rules of the game homes (c0184): pickman's meta spec, run from $h/ like every $h spec, so it reads
-- $h/src and $h/.tracker/architecture.md. The rules are the pickman-arch skill's, written and enforced once.
return require("../../../pickman/tests/meta/architecture.spec")
EOT
  if [[ $kind == lib ]]; then
    cat >"$h/default.project.json" <<EOT
{
  "name": "$h",
  "tree": {
    "\$className": "DataModel",
    "ReplicatedStorage": {
      "Arcade": { "\$path": "src/shared" }
    },
    "ServerStorage": {
      "Arcade": { "\$path": "src/server" }
    }
  }
}
EOT
    : >"$h/src/server/.gitkeep"
    cat >"$h/src/shared/Info.luau" <<'EOT'
--!strict
-- The library's identity (c0184 scaffold): the name its places carry in ReplicatedStorage.Arcade. The tree needs a
-- Luau file until its first feature; the first feature may remove this one.
return { name = "arcade" }
EOT
  else
    mkdir -p "$h/src/client"
    cat >"$h/default.project.json" <<EOT
{
  "name": "$h",
  "tree": {
    "\$className": "DataModel",
    "Players": {
      "\$properties": { "CharacterAutoLoads": false }
    },
    "ReplicatedStorage": {
      "Shared": { "\$path": "src/shared" }
    },
    "ServerScriptService": {
      "Server": { "\$path": "src/server" }
    },
    "StarterPlayer": {
      "StarterPlayerScripts": {
        "Client": { "\$path": "src/client" }
      }
    }
  }
}
EOT
    printf -- '--!strict\n-- %s'"'"'s server entry (c0184 scaffold): boots the server adapters as the features arrive.\n' "$h" >"$h/src/server/Main.server.luau"
    printf -- '--!strict\n-- %s'"'"'s client entry (c0184 scaffold): boots the client adapters as the features arrive.\n' "$h" >"$h/src/client/Main.client.luau"
  fi
}

# the root's architecture map holds one deps block (empty here), which pickman's meta spec reads; c0163's reader refuses
# a map with none
mapof() {
  local map="$1/.tracker/architecture.md"
  if ! grep -q '^```deps$' "$map"; then
    cat >>"$map" <<'EOT'

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
# no features yet
```
EOT
  fi
}

home arcade lib
for g in portal snake invaders asteroids; do home "$g" game; done
for h in arcade portal snake invaders asteroids; do mapof "$h"; done
# pickman's home has the rule's wrapper too (its other files are its own)
cat >pickman/tests/meta/home.spec.luau <<'EOT'
--!strict
-- The home rule for pickman (c0184): what every project with code has in its home (z-nile/README.md, A project's home),
-- run from this folder, so a change to the home selects it.
return require("../../../z-nile/tests/lib/homespec")
EOT
