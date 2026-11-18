#!/usr/bin/env bash
# d0406 E2: each mutant of the prototype (prototype.patch applied to origin/main) must turn a named case of
# acceptance/idea-phases.spec.luau red on an assertion. Run from z-nile/ of a scratch worktree that holds the
# prototype and this issue's acceptance folder: bash .tracker/issues/d0406/experiments/E2-mutants.sh
set -u
SPEC=.tracker/issues/d0406/acceptance/idea-phases.spec.luau
run() { ../zn run --time 280 -- lune run tests/run -- "$SPEC" 2>&1 | grep -E "^FAIL .* :: |passed," | cut -c1-200; }
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
