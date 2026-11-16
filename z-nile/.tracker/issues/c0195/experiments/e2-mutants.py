#!/usr/bin/env python3
# E2 (c0195): the mutation check. Applies each Rules-and-mutants row's mutant to the prototype (a scratch worktree
# holding the design's z-nile/lib/fence.sh and z-nile/lib/git-hooks/git), runs the acceptance spec there, and records
# whether it failed on an assertion. Usage: e2-mutants.py <prototype checkout> [<mutant id>...]
import os, subprocess, sys
proto = sys.argv[1]
only = set(sys.argv[2:])
FENCE, SHIM, SKILL = "z-nile/lib/fence.sh", "z-nile/lib/git-hooks/git", "z-nile/skills/zz-test/SKILL.md"
M = {
  "M1": (SHIM, "--cop | --copy | --mo | --mov | --move) found=1 ;;", "--mo | --mov | --move) found=1 ;;"),
  "M2": (SHIM, "[cCmM]*) found=1; break ;;", "[cCmM]) found=1; break ;;"),
  "M3": (SHIM, "-C | -c | --git-dir | --work-tree | --namespace | --config-env | --attr-source) skip=1 ;;", "-C | -c | --git-dir | --work-tree) skip=1 ;;"),
  "M4": (SHIM, "--cop | --copy | --mo | --mov | --move) found=1 ;;", "--cop | --copy) found=1 ;;\n    -m | -M | -*m* | -*M*) ;;"),
  "M5": (SHIM, '"$real" "$@" rev-parse --path-format=absolute --git-common-dir 2>/dev/null', '"$real" rev-parse --path-format=absolute --git-common-dir 2>/dev/null'),
  "M6": (SHIM, 'if [ "$common" = "$(cd "$p" 2>/dev/null && pwd -P)" ]; then', 'if true; then'),
  "M7": (SHIM, '*) what="run \'$sub\', which is not one of git\'s own commands (an alias or an external command)" ;;', '*) exec "$real" "$@" ;;'),
  "M8": (SHIM, '[ -n "$found" ] || exec "$real" "$@"', ':'),
  "M10": (FENCE, 'PATH="$hooks:$(_pickman_fence_path_without "$hooks")"', 'PATH="$hooks:$PATH"'),
  "M11": (FENCE, 'PATH="$hooks:$(_pickman_fence_path_without "$hooks")"', ':'),
  "M12": (FENCE, '[[ -n $e && $e != "$1" && ! $e -ef $1 && ! $e -ef $_pickman_fence_lib/git-hooks && -x $e/git && ! -d $e/git ]]', '[[ -n $e && -x $e/git && ! -d $e/git ]]'),
  "M12b": (FENCE, '! $e -ef $1 && ! $e -ef $_pickman_fence_lib/git-hooks && -x $e/git', '-x $e/git'),
  "M10b": (FENCE, '[[ -n $e && ( $e == "$1" || $e -ef $1 ) ]] && continue', '[[ -n $e && $e == "$1" ]] && continue'),
  "M13": (FENCE, '    [[ -n ${PICKMAN_FENCE_HOOKS:-} ]] && PATH=$(_pickman_fence_path_without "$PICKMAN_FENCE_HOOKS")\n    PATH=$(_pickman_fence_path_without "$_pickman_fence_lib/git-hooks")', '    :'),
  "M14": (FENCE, 'if [[ -z $jailed && ! -x $hooks/git ]]; then', 'if false; then'),
  "M15": (FENCE, '      if [[ -z $gitreal || -z $builtins ]]; then', '      if false; then'),
  "M16": (SHIM, 'if [ -z "$real" ] || [ ! -x "$real" ] || [ "$real" -ef "$0" ]; then', 'if [ -z "$real" ]; then real=git; fi\nif false; then'),
  "M17": (SHIM, ' || [ "$real" -ef "$0" ]; then', '; then'),
  "M18": (SKILL, "  - **Fence's git**:", "  - **Fences git**:"),
  "M19": (FENCE, '#   - where it sets those hooks, finds git first in their folder (git-hooks/git, c0195)', '#   - where it sets those hooks, finds git first in their folder'),
}
folder = ".tracker/issues/c0195/acceptance"
specs = sorted(f"{folder}/{n}" for n in os.listdir(os.path.join(proto, "z-nile", folder)) if n.endswith(".spec.luau"))
for mid, (f, a, b) in M.items():
    if only and mid not in only:
        continue
    path = os.path.join(proto, f)
    orig = open(path).read()
    assert a in orig, f"{mid}: anchor not found"
    open(path, "w").write(orig.replace(a, b, 1))
    try:
        r = subprocess.run([os.path.join(proto, "zn"), "run", "--time", "300", "--", "lune", "run", "tests/run", "--", *specs],
                           cwd=os.path.join(proto, "z-nile"), capture_output=True, text=True)
        out = r.stdout + r.stderr
        fails = [l[5:].replace(folder + "/", "")[:110] for l in out.splitlines() if l.startswith("FAIL ") and " :: " in l]
        load = "could not load" in out or "syntax error" in out
        summary = [l for l in out.splitlines() if " passed, " in l]
        print(f"{mid}: {'LOAD-ERROR ' if load else ''}{summary[-1] if summary else '?'}")
        for x in fails: print(f"    {x}")
    finally:
        open(path, "w").write(orig)
