#!/usr/bin/env bash
# d0406 E2: every mutant of the prototype turns a named case of acceptance/idea-phases.spec.luau red on an assertion.
# It works only in a clone of its own under .cache (made here, removed at the end), never in the tree it is started
# from. Run it bounded, from the checkout's top:
#   ./zn run --time 1500 -- bash z-nile/.tracker/issues/d0406/experiments/E2-mutants.sh
set -u
TOP="$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASE="$TOP/.cache/d0406-mut"
rm -rf "$BASE"; mkdir -p "$BASE"
git clone -q --no-hardlinks "$TOP" "$BASE/w" || exit 1
cd "$BASE/w" || exit 1
case "$(pwd -P)" in */.cache/d0406-mut/w) ;; *) echo "not in the clone"; exit 1 ;; esac
git checkout -q --detach "$(git -C "$TOP" rev-parse origin/main)"
git apply "$HERE/prototype.patch" || { echo "prototype does not apply"; exit 1; }
mkdir -p z-nile/tests/acceptance/d0406 && cp "$HERE/acceptance/idea-phases.spec.luau" z-nile/tests/acceptance/d0406/
cd z-nile || exit 1
run() { lune run tests/run -- tests/acceptance/d0406/idea-phases.spec.luau 2>&1 | grep -E "^FAIL .* :: |passed," | cut -c1-200; }
mutant() { # name, file, perl substitution
	cp "$2" "$2.keep"
	perl -0pi -e "$3" "$2"
	if cmp -s "$2" "$2.keep"; then echo "== $1: MUTANT DID NOT APPLY"; else echo "== $1"; run; fi
	mv "$2.keep" "$2"
}
echo "== prototype"; run
mutant "M1 ledger lists idea but not idea-challenge" engine/ledger.luau 's/, "idea", "idea-challenge" \}/, "idea" }/'
mutant "M2 ledger lists neither (the lazy rows still keep metrics alive)" engine/ledger.luau 's/, "idea", "idea-challenge" \}/ }/'
mutant "M3 metrics does not make a row for an unlisted phase (the crash)" engine/main.luau 's/\t\t\tif not phaseMin\[row\.phase\] then\n.*?\n\t\t\tend\n//s'
mutant "M4 unlisted phases are not printed" engine/main.luau 's/\tfor _, p in unlisted do\n\t\ttable\.insert\(phaseOrder, p\)\n\tend\n//'
mutant "M5 only test and other are hidden when zero" engine/main.luau 's/if not table\.find\(ledger\.PHASES, p\) and all == 0/if (p == "test" or p == "other") and all == 0/'
mutant "M6 the raft row indexes an unlisted phase unguarded" engine/main.luau 's/tenths\[row\.phase\] = \(tenths\[row\.phase\] or 0\) \+ n/tenths[row.phase] += n/'
mutant "M7 the raft row leaves unlisted and extra phases out of its total" engine/main.luau 's/(tenths\[row\.phase\] = \(tenths\[row\.phase\] or 0\) \+ n\n)\t\t\t\tallTenths \+= n/$1\t\t\t\tif table.find(ledger.PHASES, row.phase) then allTenths += n end/'
mutant "M8 every extra phase is printed even when zero" engine/main.luau 's/if not table\.find\(ledger\.PHASES, p\) and all == 0 and phaseTok\[p\] == 0 then/if false then/'
mutant "M9 metrics <id> lists no stage for an unlisted phase" engine/main.luau 's/\t\t\tfor _, p in unlistedStages do\n\t\t\t\ttable\.insert\(stageOrder, p\)\n\t\t\tend\n//'
mutant "M10 unlisted phases are printed in the order met" engine/main.luau 's/\ttable\.sort\(unlisted\)\n//'
mutant "M11 only the listed extras are hidden when zero" engine/main.luau 's/if not table\.find\(ledger\.PHASES, p\) and all == 0/if table.find(ledger.EXTRA, p) and all == 0/'
mutant "M12 unlisted stages are printed in the order met" engine/main.luau 's/\t\t\ttable\.sort\(unlistedStages\)\n//'
cd "$TOP" && rm -rf "$BASE"
