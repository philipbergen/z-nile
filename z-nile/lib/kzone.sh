#!/usr/bin/env bash
# d0426: the meter and the guard for the macOS kernel zone that spec runs leak into.
# On 2026-11-21 the owner's Mac panicked with "zone map exhausted ... data.kalloc.1024" at 20,764,352 elements in
# use. Each gate run adds a few thousand that only a reboot frees, from every session and worker on the machine.
# Sourced by z-nile/check.sh. `zprint` needs no root; where it is missing (another OS) the guard says nothing.

# The zone's in-use element count on stdout, or a non-zero exit when it cannot be read.
kzone_count() {
  command -v zprint >/dev/null 2>&1 || return 1
  zprint 2>/dev/null | awk '$1 == "data.kalloc.1024" { print $7; found = 1 } END { exit !found }'
}

# Prints the warning or the refusal on stderr. Returns 1 only to refuse.
# ZN_KZONE_WARN and ZN_KZONE_REFUSE override the levels (whole numbers); both defaults are far below the panic.
kzone_guard() {
  local n warn refuse
  # inside a spec run a fixture gate neither pays for the reading nor depends on the machine's state; a spec of this
  # guard opts in
  if [[ -n "${PICKMAN_TEST_FENCE:-}" && -z "${ZN_KZONE_IN_SPEC:-}" ]]; then
    return 0
  fi
  n="$(kzone_count)" || return 0
  [[ "$n" =~ ^[0-9]+$ ]] || return 0
  warn="${ZN_KZONE_WARN:-5000000}"
  refuse="${ZN_KZONE_REFUSE:-10000000}"
  [[ "$warn" =~ ^[0-9]+$ ]] || warn=5000000
  [[ "$refuse" =~ ^[0-9]+$ ]] || refuse=10000000
  if (( n >= refuse )); then
    echo "gate: not started: the kernel zone data.kalloc.1024 holds $n elements, at or over the refuse level $refuse (this machine panicked at 20764352). Spec runs leak into it until a reboot (d0426): save your work, reboot, then run the gate again." >&2
    return 1
  fi
  if (( n >= warn )); then
    echo "gate: a reboot is due: the kernel zone data.kalloc.1024 holds $n elements (warning level $warn, refuse level $refuse; this machine panicked at 20764352). Spec runs leak into it until a reboot (d0426)." >&2
  fi
  return 0
}
