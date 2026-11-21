# Temporary trees for shell code (c0194): everything lives under <checkout>/.cache/.tmp, never in the system temp
# folder. Source it, then:
#   tree=$(pickman_tmp_new <kind>)   # a fresh <kind>.XXXXXX in TMPDIR when that is inside a .cache/.tmp, else in this
#                                      # checkout's .cache/.tmp (no owner record: the day rule sweeps a tree left behind)
#   pickman_tmp_sweep <checkout>...             # removes the stale trees there, one report line each on stderr
# pickman_tmp_new is shell (see below); the sweep is z-nile/lib/tmp.luau's (one owner), reached through its command line,
# which needs lune on PATH.
_pickman_tmp_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
# In shell, with no Lune: the gate runs this before its tools are known to work, and its trees need no isolation. The folder
# is TMPDIR when that is inside a .cache/.tmp (a spec run's, a session's), else this checkout's. A .cache or .tmp that is a
# link or a file refuses (fence.sh's rule), the Spotlight marker is written if missing, and the tree is a fresh mktemp -d.
pickman_tmp_new() {
  local kind=$1 root cache
  case ${TMPDIR:-} in
  */.cache/.tmp | */.cache/.tmp/*) root=${TMPDIR%/} ;;
  *) root=$(pwd -P)/.cache/.tmp ;;
  esac
  cache=${root%/.tmp}
  if [[ $root == */.cache/.tmp ]] && [[ -L $cache || -L $root || -f $cache || -f $root ]]; then
    echo "tmp: $root is not a plain folder (a symlink or a file); refusing. Stop and report this." >&2
    return 1
  fi
  mkdir -p "$root" || return 1
  if [[ $root == */.cache/.tmp && ! -e $root/.metadata_never_index && ! -L $root/.metadata_never_index ]]; then
    (set -C; : >"$root/.metadata_never_index") 2>/dev/null || true
  fi
  mktemp -d "$root/$kind.XXXXXX"
}
pickman_tmp_sweep() {
  local args=() d
  for d in "$@"; do args+=(--dir "$d"); done
  lune run "$_pickman_tmp_lib/tmpcli" -- sweep ${args[@]+"${args[@]}"}
}
