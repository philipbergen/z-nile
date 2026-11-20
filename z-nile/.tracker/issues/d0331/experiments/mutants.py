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
    "finish-main-tip": (M, 'local base = (layergit.layerOneBase(raft.id, "HEAD"))', "local base = layergit.mainTip()", "layer-one"),
    "finish-parent": (M, 'local base = (layergit.layerOneBase(raft.id, "HEAD"))', 'local base = sh.git({ "rev-parse", "HEAD^" })', "layer-one"),
    "finish-diff-main-tip": (M, "local paths = layergit.diffPaths(base)", "local paths = layergit.diffPaths(if layer.position == 1 then layergit.mainTip() else base)", "layer-one"),
    "finish-upper-fork": (M, "\tif layer.position > 1 then\n\t\tlocal below = issues[layer.position - 1]", "\tif false then\n\t\tlocal below = issues[layer.position - 1]", "layer-one"),
    "start-main-tip": (L, "local baseTip, basePr =\n\t\tlayergit.layerOneBase(raft.id, if have[1] then layergit.layerTip(have[1] :: stack.Layer) else nil)\n\tlocal current", "local baseTip, basePr = layergit.raftBase(raft.id)\n\tlocal current", "layer-one"),
    "stack-main-tip": (M, "below = (layergit.layerOneBase(raftId, layergit.layerTip(have[1] :: stack.Layer), below))", "below = below", "layer-one"),
    "work-facts-main-tip": (W, "local base = if tips[1] then layergit.mainFork(tips[1].sha, mainSha) else mainSha", "local base = mainSha", "layer-one"),
    "work-stacked-main-tip": (W, "local onto = if tips[1] then layergit.mainFork(tips[1].sha, mainSha) else mainSha", "local onto = mainSha", "layer-one"),
    "trace-skeleton-main-tip": (M, "local baseTip = (layergit.layerOneBase(raft.id, localOrOriginTip(layers[1])))\n\t\tlocal onto = baseTip\n\t\tlocal topFinishSha", "local baseTip = layergit.mainTip()\n\t\tlocal onto = baseTip\n\t\tlocal topFinishSha", "layer-one"),
    "trace-check-main-tip": (M, "local baseTip = (layergit.layerOneBase(raft.id, localOrOriginTip(layers[1])))\n\tlocal onto = baseTip\n\tlocal layerHistories", "local baseTip = layergit.mainTip()\n\tlocal onto = baseTip\n\tlocal layerHistories", "layer-one"),
    "done-main-tip": (M, "onto = (\n\t\tlayergit.layerOneBase(raft.id, layergit.layerTip(layers[1]) or fail(`{layers[1].name} has no tip`))\n\t)", "onto = layergit.mainTip()", "layer-one"),
    # f0399's base commit after its raft landed (r2): the guard in layerOneBase, and the fork only on main
    "landed-base-forked": (L, "\tif not held.ok or sh.trim(held.stdout) ~= \"\" then\n\t\treturn onto, pr\n\tend\n\treturn fork, pr", "\treturn fork, pr", "on-landed"),
    # design review 002 F1, F2: the fork taken on an unlanded raft's base commit; the guard reading only the local branch
    "unlanded-base-forked": (L, '\tif pr ~= "main" then\n\t\treturn tip, pr\n\tend\n\tlocal onto = main or tip', '\tif pr ~= "main" then\n\t\treturn layergit.mainFork(firstTip or tip, tip), pr\n\tend\n\tlocal onto = main or tip', "on-landed"),
    # design review 003 F1: the guard knows the base commit by where the ref points now, or by the ref's existence
    "landed-base-current-only": (L, "\tif not held.ok or sh.trim(held.stdout) ~= \"\" then\n\t\treturn onto, pr\n\tend\n\treturn fork, pr", "\tlocal cur = layergit.shaOf(`origin/{raftId}/base`) or layergit.shaOf(`{raftId}/base`)\n\tif cur and sh.run(\"git\", { \"merge-base\", \"--is-ancestor\", cur, firstTip }).ok then\n\t\treturn onto, pr\n\tend\n\treturn fork, pr", "on-landed"),
    "landed-base-ref-exists": (L, "\tif not held.ok or sh.trim(held.stdout) ~= \"\" then\n\t\treturn onto, pr\n\tend\n\treturn fork, pr", "\tif layergit.shaOf(`origin/{raftId}/base`) or layergit.shaOf(`{raftId}/base`) then\n\t\treturn onto, pr\n\tend\n\treturn fork, pr", "on-landed"),
    "ready-on-main-tip": (M, "local below = (layergit.layerOneBase(onId, if have[1] then layergit.layerTip(have[1]) else nil))", "local below = layergit.raftBase(onId)", "on-landed"),
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
