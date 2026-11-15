#!/usr/bin/env python3
"""d0331 mutants. Usage: mutants.py <patched clone> <name>   (or: mutants.py --list)
Each mutant is one plausible wrong implementation of the prototype; proto-run.sh applies it after the patch."""
import sys

M = "z-nile/engine/main.luau"
L = "z-nile/engine/layergit.luau"
S = "z-nile/engine/stack.luau"
W = "z-nile/engine/workread.luau"

# name: (file, old, new, the spec that must fail)
MUTANTS = {
    "finish-main-tip": (M, 'local base = layergit.mainFork("HEAD")', "local base = layergit.mainTip()", "layer-one"),
    "finish-parent": (M, 'local base = layergit.mainFork("HEAD")', 'local base = sh.git({ "rev-parse", "HEAD^" })', "layer-one"),
    "finish-diff-main-tip": (M, "local paths = layergit.diffPaths(base)", "local paths = layergit.diffPaths(if layer.position == 1 then layergit.mainTip() else base)", "layer-one"),
    "finish-upper-fork": (M, "\tif layer.position > 1 then\n\t\tlocal below = issues[layer.position - 1]", "\tif false then\n\t\tlocal below = issues[layer.position - 1]", "layer-one"),
    "start-main-tip": (L, "local baseTip = if first then layergit.mainFork(first) else layergit.mainTip()\n\tlocal current", "local baseTip = layergit.mainTip()\n\tlocal current", "layer-one"),
    "stack-main-tip": (M, "below = layergit.mainFork(firstTip, below)", "below = below", "layer-one"),
    "work-facts-main-tip": (W, "local base = if tips[1] then layergit.mainFork(tips[1].sha, mainSha) else mainSha", "local base = mainSha", "layer-one"),
    "work-stacked-main-tip": (W, "local onto = if tips[1] then layergit.mainFork(tips[1].sha, mainSha) else mainSha", "local onto = mainSha", "layer-one"),
    "trace-skeleton-main-tip": (M, "local baseTip = if firstTip then layergit.mainFork(firstTip) else layergit.mainTip()\n\t\tlocal onto = baseTip\n\t\tlocal topFinishSha", "local baseTip = layergit.mainTip()\n\t\tlocal onto = baseTip\n\t\tlocal topFinishSha", "layer-one"),
    "trace-check-main-tip": (M, "local baseTip = if firstTip then layergit.mainFork(firstTip) else layergit.mainTip()\n\tlocal onto = baseTip\n\tlocal layerHistories", "local baseTip = layergit.mainTip()\n\tlocal onto = baseTip\n\tlocal layerHistories", "layer-one"),
    "done-main-tip": (M, "local onto = layergit.mainFork(firstTip)", "local onto = layergit.mainTip()", "layer-one"),
    "done-one-attempt": (S, "stack.DONE_ATTEMPTS = 9", "stack.DONE_ATTEMPTS = 1", "done-moved retry"),
    "done-unbounded": (S, "stack.DONE_ATTEMPTS = 9", "stack.DONE_ATTEMPTS = 99", "done-moved retry"),
    "done-retry-stale-main": (M, 'sh.run("git", { "fetch", "--quiet", "origin" })\n\t\t\t\tlocal now', "local now", "done-moved"),
    "done-retry-any-failure": (S, "\tif not mainMoved then\n\t\treturn \"failed\"\n\tend", "", "retry"),
    "done-conflict-no-restack": (S, "does not merge onto main: ./zn restack {raftId}, resolve", "does not merge onto main: resolve", "done-moved"),
    "done-red-no-restack": (S, "return `. If main moved under the stack: ./zn restack {raftId}`", 'return ""', "done-moved"),
    "restack-stays-on-layer": (M, "\t\t\t\tsh.git({ \"reset\", \"--hard\", before })\n\t\t\t\tif back ~= \"\" then\n\t\t\t\t\tsh.git({ \"switch\", \"--quiet\", back })\n\t\t\t\tend\n\t\t\t\tfail(stack.restackUnpushed", "\t\t\t\tsh.git({ \"reset\", \"--hard\", before })\n\t\t\t\tfail(stack.restackUnpushed", "restack-push"),
    "restack-leaves-local": (M, "\t\t\t\tsh.git({ \"reset\", \"--hard\", before })\n\t\t\t\tif back ~= \"\" then\n\t\t\t\t\tsh.git({ \"switch\", \"--quiet\", back })\n\t\t\t\tend\n\t\t\t\tfail(stack.restackUnpushed", "\t\t\t\tif back ~= \"\" then\n\t\t\t\t\tsh.git({ \"switch\", \"--quiet\", back })\n\t\t\t\tend\n\t\t\t\tfail(stack.restackUnpushed", "restack-push"),
    "restack-names-only-rejected": (M, "if other.position >= layer.position then", "if other.position == layer.position then", "restack-push"),
    "done-moved-always": (M, "stack.doneRetry(now ~= mergedOnto, attempt, #unrestored == 0)", "stack.doneRetry(true, attempt, #unrestored == 0)", "done-moved"),
    "done-merged-onto-once": (M, 'local mergedOnto = layergit.shaOf(baseRef) or ""', 'local mergedOnto = sh.git({ "merge-base", land, layergit.shaOf(baseRef) or "" })', "done-moved"),
    "done-rows-dropped": (M, "lostRows = attemptRows", "lostRows = {}", "done-moved"),
    "done-landed-unchecked": (M, 'if now == sh.git({ "rev-parse", "HEAD" }) then', "if false then", "done-push"),
    "done-lost-as-moved": (S, 'if not basesRestored then\n\t\treturn "lost"', 'if not basesRestored then\n\t\treturn "moved"', "done-push retry"),
    "restack-unnamed": (S, "the push of {layers[1] or \"?\"} was rejected; not pushed:", "a push was rejected:", "restack-push"),
}

def main():
    if sys.argv[1] == "--list":
        for name, (_, _, _, spec) in MUTANTS.items():
            print(name, spec)
        return
    root, name = sys.argv[1], sys.argv[2]
    path, old, new, _ = MUTANTS[name]
    text = open(f"{root}/{path}").read()
    if text.count(old) != 1:
        sys.exit(f"mutant {name}: anchor found {text.count(old)} times in {path}")
    open(f"{root}/{path}", "w").write(text.replace(old, new))

main()
