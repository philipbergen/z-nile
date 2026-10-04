# Sourced by the hooks here: repo_common prints the physical common git directory of the repository the hook
# runs for, by git's own rule and without starting git (hooks run on every commit and ref update of every
# fixture): GIT_DIR when git exports it (during a clone it names the new repository while the working directory
# is still the source), otherwise the working directory, which git makes the worktree root (or a bare
# repository's git directory). A linked worktree's .git file and git directory's commondir are followed; anything
# else falls back to git itself.
repo_common() {
  _d=
  if [ -n "${GIT_DIR:-}" ]; then
    _d=$GIT_DIR
  elif [ -d .git ]; then
    _d=.git
  elif [ -f .git ]; then
    read -r _g _p <.git && [ "$_g" = gitdir: ] && _d=$_p
  elif [ -d objects ] && [ -f HEAD ]; then
    _d=.
  fi
  if [ -z "$_d" ] || [ ! -d "$_d" ]; then
    git rev-parse --path-format=absolute --git-common-dir 2>/dev/null
    return
  fi
  if [ -f "$_d/commondir" ]; then
    read -r _c <"$_d/commondir"
    case $_c in /*) _d=$_c ;; *) _d=$_d/$_c ;; esac
  fi
  (cd "$_d" && pwd -P)
}
