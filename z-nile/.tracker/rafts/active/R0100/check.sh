#!/usr/bin/env bash
# Exit criteria for R0100. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; a game pull request's merger runs `z-nile/check.sh --full`, which covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0100); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0100

check "RC1: the five layers run in the Order, one wave each (c0265, c0274, c0275, c0276, c0277)" bash -c '
	out=$("$ZN_ROOT/zn" workstreams R0100) || { echo "$out"; exit 1; }
	want="c0265 wave 1 c0274 wave 2 c0275 wave 3 c0276 wave 4 c0277 wave 5"
	got=$(printf "%s\n" "$out" | grep -E "^c[0-9]+ wave" | awk "{printf \"%s %s %s \", \$1, \$2, \$3}" | sed "s/ *$//")
	[[ $got == "$want" ]] || { echo "workstreams prints: $got"; exit 1; }
	printf "%s\n" "$out" | grep -qx "parallel: no" || exit 1
	"$ZN_ROOT/zn" stack R0100 >/dev/null || { echo "zn stack R0100 refuses the Order section"; exit 1; }'

check "RC2: each interface two members share is defined once in the engine, and main.luau declares the hb table once and keeps the boardview local" bash -c '
	cd "$ZN_ROOT/z-nile/engine" || exit 1
	for def in "function heartbeat.takeoverPlan" "function heartbeat.markParse" "function heartbeat.discardParse" "function hb.judgedFor" "function hb.boardVerdicts"; do
		f=heartbeat.luau; [[ $def == *"hb."* ]] && f=main.luau
		n=$(grep -cF -e "$def" "$f"); [[ $n == 1 ]] || { echo "$def: $n definitions in $f"; exit 1; }
	done
	n=$(grep -cE "^local hb\b" main.luau); [[ $n == 1 ]] || { echo "main.luau declares the hb table $n times (a second declaration shadows the first and silently drops every function defined on it)"; exit 1; }
	grep -qE "^local boardview\b" main.luau || { echo "main.luau lost the boardview local (c0118/metrics reads it)"; exit 1; }'

check "RC3: z-run, now a shim over z-work, still carries the phrases the members pin" bash -c '
	f="$ZN_ROOT/z-nile/skills/z-run/SKILL.md"
	for p in "./zn lost" "./zn beat" "--time 3600" "--adopt" "keeps itself alive" "a lost raft" "--takeover" "you were discarded"; do
		grep -qF -e "$p" "$f" || { echo "z-run lacks: $p"; exit 1; }
	done'

check "RC4: the raft changes nothing in pickman/ or any game, and no other raft's folder" bash -c 'cd "$ZN_ROOT" && base=$(git merge-base origin/main HEAD) || { echo "no origin/main to compare with"; exit 1; }
	extra=$(git diff --name-only "$base" | grep -E "^(pickman|arcade|portal|snake|invaders|asteroids)/") || true
	other=$(git diff --name-only "$base" | grep -E "^z-nile/\.tracker/rafts/(active/|done/)?R[0-9]+/" | grep -v -E "/R0100/") || true
	[[ -z $extra && -z $other ]] || { echo "unexpected: $extra $other"; exit 1; }'

check "RC5: z-work carries the discarded-session rule" bash -c '
	f="$ZN_ROOT/z-nile/skills/z-work/SKILL.md"
	for p in "you were discarded" "./zn lost" "--adopt" "drops the raft id"; do
		grep -qF -e "$p" "$f" || { echo "z-work lacks: $p"; exit 1; }
	done'

finish
