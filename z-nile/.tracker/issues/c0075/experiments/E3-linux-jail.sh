#!/usr/bin/env bash
# Makes this Linux host able to run the spec jail (tests/lib/fence.luau): bubblewrap installed, and unprivileged user
# namespaces usable by it. Idempotent. Usage: scripts/linux-jail.sh [--apply-sysctl]
#   --apply-sysctl  where Ubuntu's kernel.apparmor_restrict_unprivileged_userns blocks bubblewrap, switch it off (a
#                   host-wide setting; CI passes it, a developer machine is told how and decides). Needs sudo.
set -euo pipefail

apply=0
case "${1:-}" in
  "") ;;
  --apply-sysctl) apply=1 ;;
  *) echo "linux-jail: unknown argument $1 (only --apply-sysctl)" >&2; exit 2 ;;
esac

[[ $(uname -s) == Linux ]] || { echo "linux-jail: not Linux; nothing to do"; exit 0; }

sudo=sudo
[[ $(id -u) == 0 ]] && sudo=
# the very jail the runner starts (fence.trialArgv), around two folders of ours, so a host that masks /proc or the like
# fails here and not after the runner has taken its lock
trial() {
  local a=${TMPDIR:-/tmp}/linux-jail.$$.a b=${TMPDIR:-/tmp}/linux-jail.$$.b rc=0
  mkdir -p "$a" "$b"
  bwrap --ro-bind / / --tmpfs /run --tmpfs /tmp --bind "$a" "$a" --bind "$b" "$b" --remount-ro /run \
    --dev /dev --proc /proc --unshare-pid --unshare-net --unshare-ipc --new-session --die-with-parent /bin/sh -c : || rc=$?
  rmdir "$a" "$b"
  return $rc
}

if ! command -v bwrap >/dev/null; then
  command -v apt-get >/dev/null ||
    { echo "linux-jail: bubblewrap (bwrap) is missing and there is no apt-get: install it with your package manager" >&2; exit 1; }
  # a fresh image may have no package index yet: update it once, then try again
  $sudo apt-get install -y bubblewrap || { $sudo apt-get update && $sudo apt-get install -y bubblewrap; }
fi

userns() { # the errors bubblewrap gives when unprivileged user namespaces are restricted (fence.linuxWhy knows the same four)
  case $1 in
    *RTM_NEWADDR* | *"setting up uid map"* | *"No permissions to create new namespace"* | *"Creating new namespace failed"*) return 0 ;;
  esac
  return 1
}

if err=$(trial 2>&1); then echo "linux-jail: bubblewrap works"; exit 0; fi
echo "linux-jail: bubblewrap cannot start a jail: $err" >&2
# only the user-namespace restriction is cured by the sysctl; anything else is the error as it stands
userns "$err" || exit 1
if ((!apply)); then
  echo "linux-jail: on Ubuntu 24.04 and later, kernel.apparmor_restrict_unprivileged_userns=1 blocks it; to switch that off for this boot, rerun with --apply-sysctl" >&2
  exit 1
fi
$sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
if err=$(trial 2>&1); then echo "linux-jail: bubblewrap works"; exit 0; fi
echo "linux-jail: still cannot start a jail: $err" >&2
exit 1
