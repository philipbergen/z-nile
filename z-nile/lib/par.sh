#!/usr/bin/env bash
# Concurrent gate stages with buffered, ordered, timed output. Sourced by z-nile/check.sh.
# Runs under bash 3.2 (macOS /bin/bash): indexed arrays, `wait <pid>`, no `wait -n`.
#   par_start <label> <command> [args...]   start the stage in the background, output to a temp file
#   par_wait                                wait for all, print each in start order as
#                                             == <label> (<s.s>s)  or  == <label> (<s.s>s, FAILED)
#                                           then its output; returns 1 if any stage failed; resets
#   par_now                                 the clock: seconds (fractional with perl, else whole)

PAR_DIR=""
PAR_N=0
PAR_LABELS=()
PAR_PIDS=()

par_now() {
  perl -MTime::HiRes=time -e 'printf "%.3f", time' 2>/dev/null || date +%s
}

par_elapsed() { # $1 start, $2 end -> "<s.s>"
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'
}

par_abort() { # Ctrl-C or TERM: stop the stages and remove the buffers
  local pid
  for pid in ${PAR_PIDS[@]+"${PAR_PIDS[@]}"}; do kill "$pid" 2>/dev/null || true; done
  [[ -z $PAR_DIR ]] || rm -rf "$PAR_DIR"
  exit 130
}

par_start() {
  local label=$1 i
  shift
  if [[ -z $PAR_DIR ]]; then
    PAR_DIR=$(mktemp -d "${TMPDIR:-/tmp}/par.XXXXXX")
    trap par_abort INT TERM
  fi
  i=$PAR_N
  PAR_N=$((PAR_N + 1))
  PAR_LABELS[$i]=$label
  (
    t0=$(par_now)
    if "$@" >"$PAR_DIR/$i.out" 2>&1; then rc=0; else rc=$?; fi
    t1=$(par_now)
    par_elapsed "$t0" "$t1" >"$PAR_DIR/$i.time"
    echo "$rc" >"$PAR_DIR/$i.rc"
  ) &
  PAR_PIDS[$i]=$!
}

par_wait() {
  local i failed=0 rc mark
  for ((i = 0; i < PAR_N; i++)); do
    wait "${PAR_PIDS[$i]}" || true
    rc=$(cat "$PAR_DIR/$i.rc" 2>/dev/null || echo 1)
    mark=""
    if [[ $rc != 0 ]]; then mark=", FAILED"; failed=1; fi
    printf '\n== %s (%ss%s)\n' "${PAR_LABELS[$i]}" "$(cat "$PAR_DIR/$i.time" 2>/dev/null || echo 0.0)" "$mark"
    cat "$PAR_DIR/$i.out"
  done
  [[ -z $PAR_DIR ]] || rm -rf "$PAR_DIR"
  trap - INT TERM
  PAR_DIR=""
  PAR_N=0
  PAR_LABELS=()
  PAR_PIDS=()
  return "$failed"
}
