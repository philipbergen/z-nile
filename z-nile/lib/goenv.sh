#!/usr/bin/env bash
# The live layer's Go toolchain, shared by the gate and gobuild.sh (f0424). Sourced.
# The toolchain is the local one only: GOTOOLCHAIN=local, so an older Go fails instead of downloading another.
export GOTOOLCHAIN=local
GO_MIN_MINOR=24 # Go 1.24 or newer (z-nile/go/go.mod, SETUP.md)

# go_status prints nothing and returns 0 when a usable Go is on PATH; returns 1 and prints why otherwise
# (no go: "absent"; too old: "old").
go_status() {
  command -v go >/dev/null 2>&1 || { echo absent; return 1; }
  local v minor
  v=$(go env GOVERSION 2>/dev/null) || { echo old; return 1; }
  v=${v#go}
  minor=${v#*.}
  minor=${minor%%[!0-9]*}
  if [[ ${v%%.*} == 1 && -n $minor && $minor -ge $GO_MIN_MINOR ]] || [[ ${v%%.*} =~ ^[0-9]+$ && ${v%%.*} -gt 1 ]]; then
    return 0
  fi
  echo old
  return 1
}
