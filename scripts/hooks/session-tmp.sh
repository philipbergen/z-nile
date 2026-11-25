#!/usr/bin/env bash
# Claude Code SessionStart hook (c0194): every Bash command this session and its subagents run gets TMPDIR under the
# project's .cache/.tmp (never the system temp folder, which Spotlight indexes) and z-nile/shim (it holds only mktemp) first on PATH, whose
# mktemp honours TMPDIR (macOS mktemp does not). Stale trees there are swept. Quiet and fail-open: a session without
# it is only back to the system temp folder, and the stale-tree report is `./zn tmp leftovers`.
export PATH="$HOME/.rokit/bin:$PATH"
top=${CLAUDE_PROJECT_DIR:-}
[[ -n $top && -n ${CLAUDE_ENV_FILE:-} && -f $top/z-nile/lib/tmpcli.luau ]] || exit 0
root=$(cd "$top" && lune run z-nile/lib/tmpcli -- root --dir "$top" 2>/dev/null) || root=
case $root in
*$'\n'* | "") root= ;;
*/.cache/.tmp) ;;
*) root= ;;
esac
if [[ -z $root ]]; then
  echo "session-tmp: could not make $top/.cache/.tmp (run ./zn tmp root to see why); TMPDIR left as it was" >&2
  exit 0
fi
{
  printf 'export TMPDIR=%q\n' "$root"
  printf 'case ":$PATH:" in *":%s:"*) ;; *) export PATH=%q:"$PATH" ;; esac\n' "$top/z-nile/shim" "$top/z-nile/shim"
} >>"$CLAUDE_ENV_FILE"
(cd "$top" && lune run z-nile/lib/tmpcli -- sweep --dir "$top" >/dev/null) || true
exit 0
