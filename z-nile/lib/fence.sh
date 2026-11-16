# Guards for everything a check runs (zz-test skill, "Specs never touch the real repository").
#   pickman_fence <checkout>          # check.sh files (z-nile/lib/ac.sh)
#   pickman_fence <checkout> specs [<jail>]   # spec runs (tests/lib/fence.luau): also no network, no credentials,
#                                             # no fetch; under the jail (<jail> = sandbox-exec) no hooks either
# <checkout> is the physical folder the checks or specs run in: the checkout's root, or a project's home inside it
# (pickman/, c0120), whose own .cache is then the fixtures' folder. After it, every git command this shell and its children run:
#   - finds no repository above <checkout>/.cache (GIT_CEILING_DIRECTORIES, plus a sentinel .cache/.git that
#     fails git run in .cache itself), so a fixture whose own repository is missing is an error;
#   - ignores inherited repository overrides (GIT_DIR, GIT_INDEX_FILE, ... are unset);
#   - refuses ref updates in the real repository (check.sh flows may still fetch into refs/remotes/)
#     (z-nile/lib/git-hooks/reference-transaction), and pushes into it by any local URL (pre-push);
#   - runs no background gc or maintenance (fixtures are throwaway, and are re-created mid-run).
# The guards accumulate: a fence set up inside another keeps the outer checkout's ceiling and ref guard.
# On macOS, tests/lib/fence.luau also runs specs in a jail that denies every write to the checkout outside .cache.
# The ref guard's hooks are the git-hooks/ folder beside this file (c0120: a project's home has none of its own).
_pickman_fence_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
# The fence, in four steps, each callable alone (c0120 review 002 F1); pickman_fence runs them in this order:
#   pickman_fence_ceiling <dir>    git never looks above <dir>/.cache: environment only, cannot fail, always first
#   pickman_fence_refusals <dir>   reads only: a .cache that isn't a plain folder, or a sentinel that is a folder,
#                                  refuses (in every mode, never waived)
#   pickman_fence_env <dir> [<mode>] [<jail>]
#                                  the git and spec guards in the environment: its one refusal (no ref guard
#                                  hooks) comes before it changes anything, and from its first change to
#                                  GIT_CONFIG_COUNT it never returns early, so a failure leaves inherited guards whole
#   pickman_fence_sentinel <dir>   the writes: .cache, the sentinel, gh's empty configuration; last, so a write the
#                                  jail refuses leaves the environment fully guarded
# git with none of the inherited variables that redirect discovery or hide the repository: every repository override
# and the ceiling. For the guards' own reads of what they protect, never for anything a check runs.
_pickman_fence_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE -u GIT_PREFIX -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
    -u GIT_CEILING_DIRECTORIES git "$@"
}

pickman_fence_ceiling() {
  case ":${GIT_CEILING_DIRECTORIES:-}:" in
  *":$1/.cache:"*) ;;
  *) export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:+$GIT_CEILING_DIRECTORIES:}$1/.cache" ;;
  esac
  return 0
}

pickman_fence_refusals() {
  local here=$1
  # .cache must be a plain folder of this checkout: a symlink there would turn every write below into a write
  # elsewhere, the real repository included (review 004 F1). Nothing here ever deletes recursively.
  if [[ -L $here/.cache || ( -e $here/.cache && ! -d $here/.cache ) ]]; then
    echo "fence: $here/.cache is not a plain folder (a symlink or a file); refusing. Stop and report this." >&2
    return 1
  fi
  # a folder at the sentinel's place could hold a commondir leading to the real repository (review 003 F2): refused,
  # not deleted
  if [[ ! -L $here/.cache/.git && -d $here/.cache/.git ]]; then
    echo "fence: $here/.cache/.git is a folder; refusing (remove it yourself after checking it). Stop and report this." >&2
    return 1
  fi
  return 0
}

pickman_fence_env() {
  local here=$1 mode=${2:-checks} jail=${3:-} real n=0 hooks=
  # inside a spec run every guard stays a spec guard: a check.sh started there keeps the spec's limits
  [[ ${PICKMAN_FENCE_SPECS:-} == 1 ]] && mode=specs
  # The hooks guard refs and pushes where no jail does: Linux, check.sh files, runs nested inside a jail. Under
  # the jail (macOS spec runs) the kernel already denies every write to the repository, and hooks would only
  # add a process start, slow inside the sandbox, to every fixture commit; fixtures' own hooks then run natively.
  if [[ $jail != sandbox-exec ]]; then
    # the first guard's hook stays in force: a nested copy may lack z-nile/lib/git-hooks
    hooks=${PICKMAN_FENCE_HOOKS:-}
    [[ -n $hooks && -x $hooks/reference-transaction ]] || hooks="$_pickman_fence_lib/git-hooks"
    # no hooks there (moved, deleted): fail closed rather than run with the ref and push guards off (c0114), except
    # inside a jailed spec run, where the kernel already refuses every write to the repository. The waiver rests on
    # all three of the runner's markers: the jail, the spec guards, and this checkout lying under the run's own .cache
    local jailed=
    if [[ ${PICKMAN_TEST_JAIL:-} == sandbox-exec && ${PICKMAN_FENCE_SPECS:-} == 1 && -n ${PICKMAN_TEST_FENCE:-} &&
      $here == "$PICKMAN_TEST_FENCE"/.cache/* ]]; then
      jailed=1
    fi
    # read-only, and before anything below changes the environment
    if [[ -z $jailed ]] && [[ ! -x $hooks/reference-transaction || ! -x $hooks/pre-push ]]; then
      echo "fence: no ref guard at $hooks (reference-transaction, pre-push); refusing. Stop and report this." >&2
      return 1
    fi
  fi
  # The repository this fence protects, read once and read-only, before anything changes: in a clean environment
  # for that one read (every inherited override, which could redirect it, code review 001 F1, and the inherited
  # ceiling, which could hide it from a project home, code review 002 F1; the shell keeps its ceiling, which nested
  # fences accumulate). Finding none refuses, in every mode: an empty answer never means "nothing to protect".
  real=$(_pickman_fence_git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || real=
  if [[ -z $real ]]; then
    echo "fence: $here is in no git repository (or git can't read it); refusing. Stop and report this." >&2
    return 1
  fi
  # From here on nothing returns early: every inherited override is replaced by the whole set at once
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  unset GIT_NAMESPACE GIT_PREFIX GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
  export PICKMAN_FENCE_REAL_GIT="${PICKMAN_FENCE_REAL_GIT:+$PICKMAN_FENCE_REAL_GIT:}$real"
  if [[ -n $hooks ]]; then
    export PICKMAN_FENCE_HOOKS=$hooks
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
    # no proxy (loopback is open in the jail, a local proxy would reach the network), and git's own protocol
    # allowlist, which overrides protocol.allow, pinned to local paths (review 002 F2, F5)
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY GIT_PROXY_COMMAND
    export GIT_ALLOW_PROTOCOL=file
    # gh's configuration folder is made by pickman_fence_sentinel; gh reads none from a missing one either
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
  return 0
}

pickman_fence_sentinel() {
  local here=$1
  mkdir -p "$here/.cache" || return 1
  # the sentinel is rewritten every time: a spec could have repointed it at the real .git (review 002 F7). A
  # symlink there is unlinked (never followed); a folder there was refused by pickman_fence_refusals
  local sentinel="$here/.cache/.git"
  [[ -L $sentinel ]] && rm -f "$sentinel"
  # written beside it and renamed in with rename(2): a rename replaces whatever is there (a link to a file or to a
  # directory) instead of writing through it. Inline, not z-nile/lib/replace-file.pl: fixtures copy this file alone
  local fresh
  fresh=$(mktemp "$here/.cache/.sentinel.XXXXXX") || return 1 # created exclusively, before any spec runs
  printf 'gitdir: /nonexistent/pickman-fence\n' >"$fresh" || { rm -f "$fresh"; return 1; }
  perl -e 'rename $ARGV[0], $ARGV[1] or die "rename: $!\n"' "$fresh" "$sentinel" || { rm -f "$fresh"; return 1; }
  if [[ ${PICKMAN_FENCE_SPECS:-} == 1 ]]; then
    mkdir -p "$here/.cache/gh-none" || return 1
  fi
  return 0
}

# A project home a check.sh runs in, inside a checkout already fenced (c0120, review 002 F1). The same four steps;
# only the last, the sentinel's write, may fail without refusing, and only where the runner's jail forbids it: all
# three of its markers (the jail, the spec guards, the run's own checkout) and <home>/.cache outside the run's own
# .cache, the one place the jail lets a spec write (review 003 F2, as c0114's `jailed` compares them); never "the write
# failed". The jail then refuses every write there, the environment is fully guarded, and git still finds no
# repository below <home>/.cache. A new jail (R0039's bwrap) adds its name to this test, with c0034's list mode as its
# regression case (review 003 F3).
pickman_home_fence() {
  local home=$1
  pickman_fence_ceiling "$home"
  pickman_fence_refusals "$home" || return 1
  pickman_fence_env "$home" || return 1
  pickman_fence_sentinel "$home" && return 0
  if [[ ${PICKMAN_TEST_JAIL:-} == sandbox-exec && ${PICKMAN_FENCE_SPECS:-} == 1 && -n ${PICKMAN_TEST_FENCE:-} &&
    $home/.cache != "$PICKMAN_TEST_FENCE"/.cache && $home/.cache != "$PICKMAN_TEST_FENCE"/.cache/* ]]; then
    echo "fence: the jail refused $home/.cache's sentinel; its ceiling and every other guard hold" >&2
    return 0
  fi
  echo "fence: cannot write $home/.cache's sentinel; refusing. Stop and report this." >&2
  return 1
}

pickman_fence() {
  local here=$1
  pickman_fence_ceiling "$here"
  pickman_fence_refusals "$here" || return 1
  pickman_fence_env "$@" || return 1
  pickman_fence_sentinel "$here" || return 1
}

# Answers whether the repository holding <dir> is one these guards protect (a check is running there): prints exactly
# `guarded` or `unguarded` and exits 0. Anything else (no answer, another exit code) means it could not tell, and the
# caller must treat that as guarded (c0114: "unguarded" is the one explicit "no"). The tracker's publisher asks this
# instead of reading the guards' variables itself (c0650).
# The one owner of the set of folders the guards cover (c0120 code review 005 F2): the checkout's top and every
# project home its registry lists (`z-nile/roots -- --projects`), one per line. The runner, the gate and ac.sh all
# take the set from here. A copy without the engine or the registry (some fixtures copy only z-nile/lib and the
# runner) lists the top folders that hold a .tracker/; only a copy without the registry itself does.
pickman_fence_dirs() {
  local top=$1 out name home root d
  printf '%s\n' "$top"
  # the registry present but its reader missing is a broken copy, never a reason to guess (code review 006 F4)
  if [[ -f $top/z-nile/projects.toml && ! -f $top/z-nile/roots.luau ]]; then
    echo "fence: $top/z-nile/projects.toml has no reader (z-nile/roots.luau); refusing to guess the homes. Stop and report this." >&2
    return 1
  fi
  if [[ -f $top/z-nile/projects.toml ]]; then
    out=$(cd "$top" && PATH="$HOME/.rokit/bin:$PATH" lune run z-nile/roots -- --projects) || {
      echo "fence: cannot read $top/z-nile/projects.toml's homes; refusing. Stop and report this." >&2
      return 1
    }
    # process substitution, not a here-string: bash writes a here-string to a temp file, which a jail may refuse
    while IFS=$'\t' read -r name home root; do
      [[ -n $home && $home != . ]] && printf '%s\n' "$top/$home"
    done < <(printf '%s\n' "$out")
    return 0
  fi
  for d in "$top"/*/; do
    if [[ -d $d.tracker ]]; then printf '%s\n' "${d%/}"; fi
  done
  return 0
}

# Fences every folder of pickman_fence_dirs <top>, in one of three modes:
#   refusals  the refusals only (reads; the gate before --plan and its builds)
#   strict    ceiling, refusals and sentinel, every failure refusing (the runner, before it enters its jail)
#   check     pickman_home_fence: the four steps, the sentinel's write waived only where the jail forbids it (ac.sh)
# Prints nothing; the set is pickman_fence_dirs'.
pickman_fence_all() {
  local top=$1 mode=$2 dirs d
  dirs=$(pickman_fence_dirs "$top") || return 1
  while IFS= read -r d; do
    [[ -n $d ]] || continue
    case $mode in
    refusals) pickman_fence_refusals "$d" || return 1 ;;
    strict)
      pickman_fence_ceiling "$d"
      pickman_fence_refusals "$d" || return 1
      pickman_fence_sentinel "$d" || { echo "fence: cannot write $d/.cache's sentinel; refusing. Stop and report this." >&2; return 1; }
      ;;
    check) pickman_home_fence "$d" || return 1 ;;
    *) echo "fence: pickman_fence_all: unknown mode $mode" >&2; return 1 ;;
    esac
  done < <(printf '%s\n' "$dirs")
}

pickman_guarded() {
  # Both ways (code review 003 F1): the clean read (no inherited override or ceiling hides the repository, code review
  # 002 F1) and the caller's own environment, which is how the caller's git will act (a GIT_DIR it set itself).
  # Guarded when either names a protected repository; exit 1 when either read fails or finds nothing (the caller
  # treats that as guarded); unguarded only when both name unprotected repositories.
  local clean own c
  clean=$(cd "$1" 2>/dev/null && _pickman_fence_git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  own=$(cd "$1" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [[ -n $clean && -n $own ]] || return 1
  for c in "$clean" "$own"; do
    c=$(cd "$c" && pwd -P) || return 1
    case ":${PICKMAN_FENCE_REAL_GIT:-}:" in
    *":$c:"*) echo guarded; return 0 ;;
    esac
  done
  echo unguarded
}

# Answers whether this process runs inside a guarded run (a spec run, or a check.sh fenced through ac.sh): prints exactly
# `checking` or `free` and exits 0. Anything else means it could not tell, and the caller treats it as `checking`
# (c0117: inside a check, ./zn dispatch starts no model CLI but a fake one under the checkout's .cache).
pickman_checking() {
  if [[ ${PICKMAN_FENCE_SPECS:-} == 1 || -n ${PICKMAN_FENCE_REAL_GIT:-} ]]; then
    echo checking
  else
    echo free
  fi
}
