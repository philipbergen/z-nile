#!/usr/bin/env bash
# Claude Code PostToolUse hook: format + lint an edited .luau file; exit 2 feeds problems back.
export PATH="$HOME/.rokit/bin:$PATH"
file=$(sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[[ $file == *.luau && -f $file ]] || exit 0
# lint with the config of the tree the file lives in (a worktree has its own), not the hook's own repo
top=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$top" || exit 0
stylua "$file" 2>&1 >/dev/null || { echo "stylua could not parse $file" >&2; exit 2; }
out=$(selene --quiet "$file" 2>&1) || { echo "$out" >&2; exit 2; }
exit 0
