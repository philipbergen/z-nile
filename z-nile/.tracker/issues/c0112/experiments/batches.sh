#!/usr/bin/env bash
# c0112: plan the workers' batches. Read-only.
#   batches.sh <repo> [--settled | --open] [max-bytes]
# An item needs a worker while `./zn lessons --uncovered` or `--unattributed` lists it. Its cost is the bytes of its
# review and refute files. Items are packed greedily, biggest first, into batches of at most max-bytes (default
# 150000); an item over that gets a batch of its own, and an item is never split between batches. Prints one line per
# batch: `batch-NN <bytes> <findings> <item> <item> ...`. `--settled` plans only items that held.sh does not hold (the
# waves before the last); `--open` plans only the held ones (the last wave, after `./zn sync`). With neither it plans all.
set -uo pipefail
repo=${1:?usage: batches.sh <repo> [--settled | --open] [max-bytes]}
shift
only=all
max=150000
for a in "$@"; do
  case $a in
    --settled) only=settled ;;
    --open) only=open ;;
    [0-9]*) max=$a ;;
    *) echo "batches.sh: unknown argument $a" >&2; exit 2 ;;
  esac
done
cd "$repo" || exit 2
heldOut=$(bash "$(dirname "${BASH_SOURCE[0]}")/held.sh" "$repo") || { echo "batches.sh: held.sh failed; no plan" >&2; exit 2; }
heldIds=$(printf '%s\n' "$heldOut" | awk '$1 != "held:" {print $1}')
# `./zn lessons --uncovered` and `--unattributed` exit 1 when they list something, and so does lune on an uncaught error:
# the status alone cannot tell them apart. Exit 0 is a result; exit 1 is a result only when every output line is a
# listing (`<item> <review> <finding>` or `<item> note <text>`); anything else is an error and stops the plan.
list() {
  local out rc bad
  out=$(./zn lessons "$1" 2>&1) && rc=0 || rc=$?
  if ((rc > 1)); then echo "batches.sh: ./zn lessons $1 failed (exit $rc): $out" >&2; return 2; fi
  if ((rc == 1)); then
    bad=$(printf '%s\n' "$out" | grep -v -E '^[A-Za-z]+[0-9]+ (design-review-|review-|stream-review-|focused-review-|note )' | grep -v '^$' | head -1)
    if [[ -n $bad ]]; then echo "batches.sh: ./zn lessons $1 failed (exit 1): $bad" >&2; return 2; fi
  fi
  printf '%s\n' "$out"
}
unc=$(list --uncovered) || exit 2
una=$(list --unattributed) || exit 2
todo=$(printf '%s\n%s\n' "$unc" "$una" | awk '$1 ~ /^[A-Za-z]+[0-9]+$/ {print $1}' | sort -u)
[[ -n $todo ]] || { echo "nothing to do"; exit 0; }
rows=
for item in $todo; do
  dir=$(./zn find "$item" 2>/dev/null) || { echo "no item $item" >&2; exit 1; }
  if printf '%s\n' "$heldIds" | grep -qx "$item"; then kind=open; else kind=settled; fi
  [[ $only == all || $only == "$kind" ]] || continue
  bytes=$(cat "$dir"/design-review-[0-9]*.md "$dir"/review-[0-9]*.md "$dir"/stream-review-*.md "$dir"/focused-review-[0-9]*.md \
    "$dir"/design-refute-[0-9]*.md "$dir"/refute-[0-9]*.md "$dir"/stream-refute-*.md 2>/dev/null | wc -c | tr -d ' ')
  n=$(cat "$dir"/design-review-[0-9]*.md "$dir"/review-[0-9]*.md "$dir"/stream-review-*.md "$dir"/focused-review-[0-9]*.md 2>/dev/null | grep -c '^### F')
  rows+="$bytes $n $item"$'\n'
done
printf '%s' "$rows" | sort -rn | awk -v max="$max" '
  { bytes[NR]=$1; n[NR]=$2; item[NR]=$3 }
  END {
    for (i = 1; i <= NR; i++) {
      placed = 0
      for (b = 1; b <= nb; b++) if (size[b] + bytes[i] <= max) { size[b] += bytes[i]; cnt[b] += n[i]; list[b] = list[b] " " item[i]; placed = 1; break }
      if (!placed) { nb++; size[nb] = bytes[i]; cnt[nb] = n[i]; list[nb] = " " item[i] }
    }
    for (b = 1; b <= nb; b++) printf "batch-%02d %d %d%s\n", b, size[b], cnt[b], list[b]
  }'
