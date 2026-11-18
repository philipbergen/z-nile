#!/usr/bin/env bash
# d0413 E2: every mutant of the prototype turns a case of acceptance/loops.spec.luau red. It works only in a clone of
# its own under .cache (made here, removed at the end), never in the tree it is started from. Run it bounded, from
# the checkout's top:  ./zn run --time 900 -- bash z-nile/.tracker/issues/d0413/experiments/E2-mutants.sh
set -u
TOP="$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASE="$TOP/.cache/d0413-mut"
rm -rf "$BASE"; mkdir -p "$BASE"
git clone -q --no-hardlinks "$TOP" "$BASE/w" || exit 1
cd "$BASE/w" || exit 1
case "$(pwd -P)" in */.cache/d0413-mut/w) ;; *) echo "not in the clone"; exit 1 ;; esac
git checkout -q --detach "$(git -C "$TOP" rev-parse origin/main)"
git apply "$HERE/prototype.patch" || { echo "prototype does not apply"; exit 1; }
mkdir -p z-nile/tests/acceptance/d0413 && cp "$HERE/acceptance/loops.spec.luau" z-nile/tests/acceptance/d0413/
cd z-nile || exit 1
run() { lune run tests/run -- tests/acceptance/d0413/loops.spec.luau 2>&1 | grep -E "^FAIL .* :: |passed," | cut -c1-220; }
mutant() { # name, file, perl substitution
	cp "$2" "$2.keep"
	perl -0pi -e "$3" "$2"
	if cmp -s "$2" "$2.keep"; then echo "== $1: MUTANT DID NOT APPLY"; else echo "== $1"; run; fi
	mv "$2.keep" "$2"
}
echo "== prototype"; run
mutant "M1 guesses keeps trailing empty lines" engine/guesses.luau 's/\tfor at = #lines, 1, -1 do\n.*?\n\tend\n//s'
mutant "M2 guesses drops every empty line, not only trailing ones" engine/guesses.luau 's/\t\tif lines\[at\] ~= "" then\n\t\t\tbreak\n\t\tend\n\t\tlines\[at\] = nil/\t\tif lines[at] == "" then\n\t\t\ttable.remove(lines, at)\n\t\tend/'
mutant "M3 the planner ignores dependencies" engine/raftplan.luau 's/if listed\[d\] and not met\[d\] and d ~= i\.id then/if false then/'
mutant "M4 an issue that names itself waits for itself" engine/raftplan.luau 's/if listed\[d\] and not met\[d\] and d ~= i\.id then/if listed[d] and not met[d] then/'
mutant "M5 a ring takes the last entry left, not the first" engine/raftplan.luau 's/(\t\t\tfor at in issues do\n\t\t\t\tif not taken\[at\] then\n\t\t\t\t\tpick = at\n)\t\t\t\t\tbreak\n/$1/'
mutant "M6 an entry is taken by id, so a repeated id is planned once" engine/raftplan.luau 's/if taken\[at\] then/if taken[at] or met[i.id] then/'
mutant "M7 a dependency outside the list holds an issue back" engine/raftplan.luau 's/if listed\[d\] and not met\[d\] and d ~= i\.id then/if not met[d] and d ~= i.id then/'
mutant "M8 the passes stop one short" engine/raftplan.luau 's/for _ = 1, #issues do/for _ = 2, #issues do/'
git checkout -q -- engine && echo "== M9 main's loops (the prototype reverted)" && run
cd "$TOP" && rm -rf "$BASE"
