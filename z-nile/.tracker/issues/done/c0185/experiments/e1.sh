#!/usr/bin/env bash
# c0185 E1 (run in prep, 2026-11-01): do `rojo build`, `rojo sourcemap`, `luau-lsp analyze` and `rojo serve` accept a "$path"
# outside the home? (Beta.project's absolute-path copy is E1c in the issue.) Usage: bash e1.sh <empty scratch folder> <globalTypes.d.luau> <checkout top>
# (the top supplies rokit.toml: the rokit shims run only where a manifest is above them)
# Writes only under the scratch folder; stops its own rojo serve; run it under a time bound. The last lines are PASS or FAIL.
set -uo pipefail
T=$1 DEFS=$2 TOP=$3
mkdir -p "$T/arcade/src/shared/Logic/Rng" "$T/arcade/src/server" "$T/game/src/shared/Logic" "$T/game/src/server" "$T/game/src/client"
cd "$T"
cp "$TOP/rokit.toml" "$T/rokit.toml"
printf '%s\n' '--!strict' 'local Rng = {}' 'function Rng.next(seed: number): number' '	return (seed * 1103515245 + 12345) % 2147483648' 'end' 'return Rng' >arcade/src/shared/Logic/Rng/init.luau
printf '%s\n' '--!strict' 'return { name = "receipts" }' >arcade/src/server/Receipts.luau
printf '%s\n' '--!strict' 'return { name = "game" }' >game/src/shared/Logic/Info.luau
printf '%s\n' '--!strict' 'local Rng = require("@game/ReplicatedStorage/Arcade/Logic/Rng")' 'local Receipts = require("@game/ServerStorage/Arcade/Receipts")' 'print(Rng.next(1), Receipts.name)' >game/src/server/Main.server.luau
printf '%s\n' '--!strict' 'local Rng = require("@game/ReplicatedStorage/Arcade/Logic/Rng")' 'print(Rng.next(2))' >game/src/client/Main.client.luau
printf '%s\n' '{ "name": "game", "tree": { "$className": "DataModel",
  "ReplicatedStorage": { "Shared": { "$path": "src/shared" }, "Arcade": { "$path": "../arcade/src/shared" } },
  "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } },
  "ServerScriptService": { "Server": { "$path": "src/server" } },
  "StarterPlayer": { "StarterPlayerScripts": { "Client": { "$path": "src/client" } } } } }' >game/default.project.json
printf '%s\n' '{"languageMode":"strict"}' >.luaurc
fail=0
step() { local name=$1; shift; if "$@" >"$T/$name.log" 2>&1; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi; }
cd game
step build rojo build default.project.json -o ../out.rbxl
step sourcemap rojo sourcemap default.project.json -o sourcemap.json
grep -q '../arcade/src/shared/Logic/Rng/init.luau' sourcemap.json && echo "ok   sourcemap names the library's files" || { echo "FAIL sourcemap names no library file"; fail=1; }
step analyze luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json --base-luaurc=../.luaurc --ignore='**/_Index/**' src
# the library's types are followed: a wrong argument type across the homes is an error, and so is a path that is not there
sed -i.bak 's/Rng.next(2)/Rng.next("x")/' src/client/Main.client.luau
luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json --base-luaurc=../.luaurc --ignore='**/_Index/**' src >"$T/types.log" 2>&1 && { echo "FAIL a wrong type across homes passed"; fail=1; } || { grep -q "Expected this to be 'number'" "$T/types.log" && echo "ok   a wrong type across homes is an error" || { echo "FAIL no type error"; fail=1; }; }
mv src/client/Main.client.luau.bak src/client/Main.client.luau
# rojo serve reads the library's files too (7.x speaks msgpack, so the sources are looked for as strings)
rojo serve default.project.json --port 34871 >"$T/serve.log" 2>&1 &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do sleep 0.5; curl -s -m 2 http://127.0.0.1:34871/api/rojo >"$T/api.bin" && break; done
id=$(python3 -I -c "
b=open('$T/api.bin','rb').read(); i=b.index(b'rootInstanceId')+len('rootInstanceId')
print(b[i+2:i+34].decode() if b[i] in (0xd9, 0xda) else b[i+1:i+33].decode())")
curl -s -m 5 "http://127.0.0.1:34871/api/read/$id" >"$T/read.bin"
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
strings -a "$T/read.bin" | grep -q 'function Rng.next' && strings -a "$T/read.bin" | grep -q 'receipts' && echo "ok   serve serves the library's modules" || { echo "FAIL serve"; fail=1; }
[[ $fail == 0 ]] && echo "PASS E1" || echo "FAIL E1"
exit $fail
