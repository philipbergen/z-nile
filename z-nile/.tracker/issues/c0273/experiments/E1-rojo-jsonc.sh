#!/usr/bin/env bash
# c0273 E1: what Rojo 7.7.1 does with *.project.jsonc. Run from anywhere, bounded:
#   ./zn run --time 60 -- bash z-nile/.tracker/issues/c0273/experiments/E1-rojo-jsonc.sh
# Everything it writes is under <checkout>/.cache/c0273-probe/e1, its own fixture.
set -u
F="$(git rev-parse --show-toplevel)/.cache/c0273-probe/e1"
rm -rf "$F" && mkdir -p "$F" && cd "$F" || exit 1
mkdir -p h1/src h2/src h3/src h4/src/Sub out
for h in h1 h2 h3 h4; do echo 'return 1' > $h/src/a.luau; done
echo 'return 2' > out/o.luau
cat > h1/x.project.jsonc <<'J'
{
  // a comment
  "name": "x",
  "tree": { "$className": "DataModel", "ReplicatedStorage": { "S": { "$path": "src" } }, },
}
J
cp h1/x.project.jsonc h1/c.project.json
echo "P1 build a commented *.project.jsonc:"; rojo build h1/x.project.jsonc -o "$F/p1.rbxl" >/dev/null 2>&1 && echo ok || echo FAIL
echo "P2 sourcemap it:"; rojo sourcemap --include-non-scripts h1/x.project.jsonc; echo
echo "P3 build a commented *.project.json:"; rojo build h1/c.project.json -o "$F/p3.rbxl" >/dev/null 2>&1 && echo ok || echo FAIL
printf '{"name":"d","tree":{"$className":"DataModel","ReplicatedStorage":{"J":{"$path":"src"}}}}' > h2/default.project.jsonc
echo "P4 a folder with default.project.jsonc only:"; rojo sourcemap h2 2>&1; echo
printf '{"name":"d","tree":{"$className":"DataModel","ReplicatedStorage":{"FromJson":{"$path":"src"}}}}' > h3/default.project.json
printf '{"name":"d","tree":{"$className":"DataModel","ReplicatedStorage":{"FromJsonc":{"$path":"src"}}}}' > h3/default.project.jsonc
echo "P5 a folder with both defaults:"; rojo sourcemap h3 2>&1; echo
printf '{"name":"n","tree":{"$path":"../../../out"}}' > h4/src/Sub/default.project.jsonc
printf '{"name":"d","tree":{"$className":"DataModel","ReplicatedStorage":{"S":{"$path":"src"}}}}' > h4/default.project.json
echo "P6 a default.project.jsonc nested in a mapped folder:"; rojo sourcemap --include-non-scripts h4/default.project.json 2>&1; echo
