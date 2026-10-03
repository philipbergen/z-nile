# Guards for everything a check runs (testing skill, "Specs never touch the real repository").
#   pickman_fence <checkout>          # check.sh files (scripts/lib/ac.sh)
#   pickman_fence <checkout> specs [<jail>]   # spec runs (tests/lib/fence.luau): also no network, no credentials,
#                                             # no fetch; under the jail (<jail> = sandbox-exec) no hooks either
# <checkout> is the checkout's physical root. After it, every git command this shell and its children run:
#   - finds no repository above <checkout>/.cache (GIT_CEILING_DIRECTORIES, plus a sentinel .cache/.git that
#     fails git run in .cache itself), so a fixture whose own repository is missing is an error;
#   - ignores inherited repository overrides (GIT_DIR, GIT_INDEX_FILE, ... are unset);
#   - refuses ref updates in the real repository (check.sh flows may still fetch into refs/remotes/)
#     (scripts/lib/git-hooks/reference-transaction), and pushes into it by any local URL (pre-push);
#   - runs no background gc or maintenance (fixtures are throwaway, and are re-created mid-run).
# The guards accumulate: a fence set up inside another keeps the outer checkout's ceiling and ref guard.
# On macOS, tests/lib/fence.luau also runs specs in a jail that denies every write to the checkout outside .cache.
pickman_fence() {
  local here=$1 mode=${2:-checks} jail=${3:-} real n=0
  # inside a spec run every guard stays a spec guard: a check.sh started there keeps the spec's limits
  [[ ${PICKMAN_FENCE_SPECS:-} == 1 ]] && mode=specs
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  unset GIT_NAMESPACE GIT_PREFIX GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
  real=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || real=
  export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:+$GIT_CEILING_DIRECTORIES:}$here/.cache"
  mkdir -p "$here/.cache"
  [[ -e $here/.cache/.git ]] || printf 'gitdir: /nonexistent/pickman-fence\n' >"$here/.cache/.git"
  if [[ -n $real ]]; then
    export PICKMAN_FENCE_REAL_GIT="${PICKMAN_FENCE_REAL_GIT:+$PICKMAN_FENCE_REAL_GIT:}$real"
  fi
  # The hooks guard refs and pushes where no jail does: Linux, check.sh files, runs nested inside a jail. Under
  # the jail (macOS spec runs) the kernel already denies every write to the repository, and hooks would only
  # add a process start, slow inside the sandbox, to every fixture commit; fixtures' own hooks then run natively.
  if [[ $jail != sandbox-exec ]]; then
    # the first guard's hook stays in force: a nested copy may lack scripts/lib/git-hooks
    [[ -n ${PICKMAN_FENCE_HOOKS:-} && -x $PICKMAN_FENCE_HOOKS/reference-transaction ]] ||
      export PICKMAN_FENCE_HOOKS="$here/scripts/lib/git-hooks"
    export "GIT_CONFIG_KEY_$n=core.hooksPath" "GIT_CONFIG_VALUE_$n=$PICKMAN_FENCE_HOOKS"
    n=$((n + 1))
  fi
  export "GIT_CONFIG_KEY_$n=gc.auto" "GIT_CONFIG_VALUE_$n=0"
  n=$((n + 1))
  export "GIT_CONFIG_KEY_$n=maintenance.auto" "GIT_CONFIG_VALUE_$n=false"
  n=$((n + 1))
  if [[ $mode == specs ]]; then
    # a spec never reaches the network: pushes go only into local fixtures (pre-push), and there are no
    # credentials to use: no GitHub tokens, an empty gh configuration, no git credential helper (the system
    # gitconfig may name the keychain), no ssh agent and no ssh at all
    export PICKMAN_FENCE_SPECS=1
    unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN SSH_AUTH_SOCK
    mkdir -p "$here/.cache/gh-none"
    export GH_CONFIG_DIR="$here/.cache/gh-none" GIT_TERMINAL_PROMPT=0
    export GIT_SSH_COMMAND='echo "fence: a spec tried to use ssh; refused" >&2; exit 1; :'
    export "GIT_CONFIG_KEY_$n=credential.helper" "GIT_CONFIG_VALUE_$n="
    n=$((n + 1))
    # no network at all, hooks or not: git may use only local repositories (any spelling of a URL, a pushurl or an
    # insteadOf alias resolves to a transport, and every transport but file is refused)
    export "GIT_CONFIG_KEY_$n=protocol.allow" "GIT_CONFIG_VALUE_$n=never"
    n=$((n + 1))
    export "GIT_CONFIG_KEY_$n=protocol.file.allow" "GIT_CONFIG_VALUE_$n=always"
    n=$((n + 1))
  fi
  export GIT_CONFIG_COUNT=$n
}
