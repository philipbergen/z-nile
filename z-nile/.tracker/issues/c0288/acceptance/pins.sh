#!/usr/bin/env bash
# c0288's pins over c0260's specs, run by check.sh from z-nile/ (ac.sh's home). Reads only. The specs are found where
# they are: c0260's acceptance/ folder while it is unfinished, its promoted tests/acceptance/c0260 once it is done
# (`./zn find c0260`, from this folder, as check.sh's home). The values (the floor) come from check.sh, so they are in
# the approved contract; this file holds only the logic.
#   bash pins.sh limits <floor> [dir]
#     every stall_seconds or tool_seconds line in any c0260 spec is a plain `<name> = <n>`, optionally ending in the
#     marker `# tests a stall`; n >= floor unless marked. A limit in any other form fails (it cannot be read).
#   bash pins.sh shape <floor> [dir [base]]
#     the branch changes c0260's specs only in limit lines: from base (default: the merge base of HEAD and origin/main)
#     no spec is added, deleted or renamed, every changed line is a plain limit line, and every added one is at least
#     the floor and unmarked (only c0260's own design may mark a case that tests a stall). An empty change passes.
#   (dir and base are for the mutation check's scratch copies; check.sh passes neither.)
set -euo pipefail
mode=${1:-} floor=${2:-} dir=${3:-} base=${4:-}
[[ $floor =~ ^[0-9]+$ ]] || { echo "usage: pins.sh limits|shape <floor> [dir [base]]" >&2; exit 2; }
if [[ -z $dir ]]; then
  found=$("$ZN_ROOT/zn" find c0260)
  if [[ -d $found/acceptance ]]; then dir=$found/acceptance
  elif [[ -d tests/acceptance/c0260 ]]; then dir=tests/acceptance/c0260
  else echo "c0260's specs are in neither $found/acceptance nor tests/acceptance/c0260"; exit 1; fi
fi
limit='^[[:space:]]*(stall_seconds|tool_seconds)[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*(# tests a stall)?[[:space:]]*$'
bad=0
case $mode in
limits)
  shopt -s nullglob
  specs=("$dir"/*.spec.luau)
  [[ ${#specs[@]} -gt 0 ]] || { echo "no specs in $dir"; exit 1; }
  while IFS= read -r hit; do
    line=${hit#*:*:}
    if [[ $line =~ $limit ]]; then
      if [[ -z ${BASH_REMATCH[3]} ]] && (( BASH_REMATCH[2] < floor )); then echo "short limit: $hit"; bad=1; fi
    else
      echo "a limit set in a form this pin cannot read: $hit"; bad=1
    fi
  done < <(grep -nHE "stall_seconds|tool_seconds" "${specs[@]}" || true)
  ;;
shape)
  [[ -n $base ]] || base=$(git merge-base HEAD origin/main)
  while IFS= read -r st; do
    [[ -z $st || $st == M$'\t'* ]] || { echo "not a change in place: $st"; bad=1; }
  done < <(git diff --no-renames --name-status "$base" -- "$dir")
  while IFS= read -r new; do
    [[ -z $new ]] || { echo "a file the base does not have: $new"; bad=1; }
  done < <(git ls-files --others --exclude-standard -- "$dir")
  while IFS= read -r line; do
    case $line in '+++ '* | '--- '*) continue ;; [+-]*) ;; *) continue ;; esac
    body=${line:1}
    if [[ ! $body =~ $limit ]]; then echo "a changed line that is not a limit: $line"; bad=1
    elif [[ $line == +* && ( -n ${BASH_REMATCH[3]} || BASH_REMATCH[2] -lt floor ) ]]; then
      echo "an added limit below $floor or marked: $line"; bad=1
    fi
  done < <(git diff --no-renames --no-color -U0 "$base" -- "$dir")
  ;;
*) echo "usage: pins.sh limits|shape <floor> [dir [base]]" >&2; exit 2 ;;
esac
exit $bad
