#!/usr/bin/env bash
# fsevents-meter (c0179): count file events under root folders while a command runs, and report the
# CPU-seconds fseventsd spent over that window beside an idle window of the same length.
#
#   fsevents-meter.sh [--limit <seconds>] [--no-idle] [--by-folder <depth>] --root <dir> [--root <dir> ...] -- <command> [args...]
#
# stdout, tab separated, one line each (machine readable):
#   events <TAB> <count> <TAB> <root as given>        one per root
#   folder <TAB> <count> <TAB> <path>                 with --by-folder <depth>: events by the first <depth> folders under a root
#   fseventsd-cpu-seconds <TAB> run <TAB> <seconds>
#   fseventsd-cpu-seconds <TAB> idle <TAB> <seconds>  (absent with --no-idle)
#   wall-seconds <TAB> run <TAB> <seconds>
#   status <TAB> <command's exit status, or 124 when the limit stopped it>
# Exit: the command's own status when the metering worked (0 or the command's), else
#   64 usage, 65 a root does not exist or cannot be watched, 66 swiftc is missing (one line says so),
#   67 the helper did not build or start, 0 with "meter: not available on this host" off macOS.
#
# Reads only. Its one write is the Swift helper it builds on first use into <checkout>/.cache/bin/ (a
# 15-line FSEvents client, fsevents-meter.swift beside this file); no admin rights, no download.
# Bounded: it ends when the command ends or at --limit (default 600 s), and stops everything it started.
# Test seams (the spec uses them): FSEVENTS_METER_UNAME (host name), FSEVENTS_METER_SWIFTC (compiler),
# FSEVENTS_METER_HELPER (a ready-made helper: nothing is built), FSEVENTS_METER_CACHE (the bin's parent).
set -u

say() { printf '%s\n' "$*" >&2; }
usage() { say "usage: fsevents-meter.sh.sh [--limit <seconds>] [--no-idle] [--by-folder <depth>] --root <dir> [--root <dir> ...] -- <command> [args...]"; }

limit=600
idle=1
roots=()
while [ $# -gt 0 ]; do
  case "$1" in
    --limit) [ $# -ge 2 ] || { usage; exit 64; }; limit="$2"; shift 2 ;;
    --no-idle) idle=0; shift ;;
    --by-folder) [ $# -ge 2 ] || { usage; exit 64; }; export FSEVENTS_METER_DEPTH="$2"; shift 2 ;;
    --root) [ $# -ge 2 ] || { usage; exit 64; }; roots+=("$2"); shift 2 ;;
    --) shift; break ;;
    -h | --help) usage; exit 0 ;;
    *) say "fsevents-meter: unknown argument '$1'"; usage; exit 64 ;;
  esac
done
[ ${#roots[@]} -ge 1 ] || { say "fsevents-meter: name at least one --root"; usage; exit 64; }
[ $# -ge 1 ] || { say "fsevents-meter: name a command after --"; usage; exit 64; }
case "$limit" in '' | *[!0-9]*) say "fsevents-meter: --limit takes whole seconds, not '$limit'"; exit 64 ;; esac
[ "$limit" -ge 1 ] || { say "fsevents-meter: --limit must be at least 1"; exit 64; }

host="${FSEVENTS_METER_UNAME:-$(uname -s)}"
if [ "$host" != Darwin ]; then
  say "meter: not available on this host ($host has no FSEvents); skipped, the command was not run"
  exit 0
fi

for r in "${roots[@]}"; do
  [ -d "$r" ] || { say "fsevents-meter: root '$r' does not exist (or is not a folder)"; exit 65; }
done

here="$(cd "$(dirname "$0")" && pwd -P)"
checkout="$(cd "$here/../.." && pwd -P)"
bin="${FSEVENTS_METER_CACHE:-$checkout/.cache}/bin"
helper="${FSEVENTS_METER_HELPER:-$bin/fsevents-meter-helper}"
if [ -z "${FSEVENTS_METER_HELPER:-}" ] && { [ ! -x "$helper" ] || [ "$here/fsevents-meter.swift" -nt "$helper" ]; }; then
  swiftc="${FSEVENTS_METER_SWIFTC:-swiftc}"
  command -v "$swiftc" > /dev/null 2>&1 || { say "meter: swiftc is missing (install the Xcode command line tools); cannot build the FSEvents helper"; exit 66; }
  mkdir -p "$bin/swift-modules" || { say "fsevents-meter: cannot create $bin"; exit 67; }
  if ! CLANG_MODULE_CACHE_PATH="$bin/swift-modules" "$swiftc" -O -module-cache-path "$bin/swift-modules" \
    -o "$helper.$$" "$here/fsevents-meter.swift" 2> "$helper.$$.log"; then
    say "fsevents-meter: the helper did not build; see $helper.$$.log"
    exit 67
  fi
  rm -f "$helper.$$.log"
  mv -f "$helper.$$" "$helper"
fi
[ -x "$helper" ] || { say "fsevents-meter: helper '$helper' is not executable"; exit 67; }

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
# fseventsd's cumulative CPU-seconds ("M:SS.ss", "H:MM:SS.ss" or "D-HH:MM:SS"), or 0 when it is not found.
cpu() {
  local pid
  pid="$(pgrep -x fseventsd 2> /dev/null | head -n 1)"
  [ -n "$pid" ] || { echo 0; return; }
  ps -o cputime= -p "$pid" 2> /dev/null | awk '{
    t = $1; d = 0
    if (index(t, "-")) { split(t, a, "-"); d = a[1]; t = a[2] }
    n = split(t, p, ":"); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + p[i]
    printf "%.2f\n", s + d * 86400 }'
}

work="$(mktemp -d "${TMPDIR:-/tmp}/fsevents-meter.XXXXXX")" || exit 67
hpid=""
cpid=""
# The command runs as the leader of a process group of its own (set -m), so its children, which may outlive it, are in that
# group: they are stopped (TERM, then KILL) whenever the command ends, whatever way it ended (c0179 review F3).
stop_group() {
  [ -n "$cpid" ] || return 0
  kill -TERM -- "-$cpid" 2> /dev/null
  sleep 0.2
  kill -KILL -- "-$cpid" 2> /dev/null
  cpid=""
}
cleanup() {
  stop_group
  [ -n "$hpid" ] && kill -KILL "$hpid" 2> /dev/null
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

"$helper" "$work/ready" "${roots[@]}" > "$work/events" 2> "$work/err" &
hpid=$!
waited=0
while [ ! -e "$work/ready" ]; do
  kill -0 "$hpid" 2> /dev/null || { say "fsevents-meter: the helper stopped: $(head -n 1 "$work/err")"; hpid=""; exit 65; }
  [ "$waited" -lt 100 ] || { say "fsevents-meter: the helper was not ready after 10 s"; exit 67; }
  sleep 0.1
  waited=$((waited + 1))
done

cpu0="$(cpu)"
t0="$(now)"
set -m
"$@" &
cpid=$!
set +m
status=""
while [ -z "$status" ]; do
  if ! kill -0 "$cpid" 2> /dev/null; then
    wait "$cpid"
    status=$?
    break
  fi
  if awk -v a="$t0" -v b="$(now)" -v l="$limit" 'BEGIN { exit !(b - a >= l) }'; then
    kill -TERM -- "-$cpid" 2> /dev/null
    sleep 0.5
    kill -KILL -- "-$cpid" 2> /dev/null
    wait "$cpid" 2> /dev/null
    status=124
    say "fsevents-meter: the command was stopped at the ${limit} s limit"
    break
  fi
  sleep 0.1
done
t1="$(now)"
cpu1="$(cpu)"
stop_group

kill -TERM "$hpid" 2> /dev/null
stopped=0
while kill -0 "$hpid" 2> /dev/null && [ "$stopped" -lt 100 ]; do
  sleep 0.1
  stopped=$((stopped + 1))
done
if kill -0 "$hpid" 2> /dev/null; then
  kill -KILL "$hpid" 2> /dev/null
  say "fsevents-meter: the helper did not stop within 10 s; the counts are lost"
fi
wait "$hpid" 2> /dev/null
hpid=""

wall="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }')"
run_cpu="$(awk -v a="$cpu0" -v b="$cpu1" 'BEGIN { printf "%.2f", b - a }')"
while IFS="$(printf '\t')" read -r count root rest; do
  if [ "$count" = folder ]; then printf 'folder\t%s\t%s\n' "$root" "$rest"; else [ -n "$root" ] && printf 'events\t%s\t%s\n' "$count" "$root"; fi
done < "$work/events"
printf 'fseventsd-cpu-seconds\trun\t%s\n' "$run_cpu"
if [ "$idle" = 1 ]; then
  i0="$(cpu)"
  sleep "$wall"
  i1="$(cpu)"
  printf 'fseventsd-cpu-seconds\tidle\t%s\n' "$(awk -v a="$i0" -v b="$i1" 'BEGIN { printf "%.2f", b - a }')"
fi
printf 'wall-seconds\trun\t%s\n' "$wall"
printf 'status\t%s\n' "$status"
exit "$status"
