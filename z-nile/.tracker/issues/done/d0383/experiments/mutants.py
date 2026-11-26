#!/usr/bin/env python3
"""d0383 mutation check. Run from the PROTO checkout's z-nile/ as
  ./zn run --time 3300 -- python3 -I <this file> <proto-checkout> <out.tsv> [--check] [N4,N5 ...]
Edits only files of the PROTO checkout (a detached throwaway worktree), runs one spec file per mutant from its z-nile/
(`lune run tests/run -- <spec>`), records the FAIL lines, and puts every file back (also on error). It commits, resets and
cleans nothing. --check only verifies that every edit applies exactly once."""
import subprocess, sys, os

args = [a for a in sys.argv[1:] if a != "--check"]
check_only = "--check" in sys.argv
proto, out = args[0], args[1]
only = args[2].split(",") if len(args) > 2 else None
Z = os.path.join(proto, "z-nile")
ACC = ".tracker/issues/d0383/acceptance/"
K, L, S, R = (ACC + "watch-net-kick.spec.luau", ACC + "watch-net-lock.spec.luau", ACC + "watch-net-stale.spec.luau", ACC + "watch-net-reaper.spec.luau")
W, B, M, P = "engine/watchcmd.luau", "engine/board.luau", "lib/watch.luau", "engine/reap.luau"

MUTANTS = [
 ("M1 net dir relative again", K, [(W, "local WT = watch.netDir(mainDir())", 'local WT = ".worktree/watch-net"')]),
 ("M2 main checkout taken as the current worktree's top", K, [(W, "local main = if listed.ok then watch.mainCheckout(listed.stdout) else nil", 'local main = sh.trim(sh.run("git", { "rev-parse", "--show-toplevel" }).stdout)')]),
 ("M3 kick returns without waiting", K, [(W, 'if state ~= "waiting" or os.time() >= deadline then', "if true then")]),
 ("M3c kick shell keeps the net in the call's pipes (cd && group &)", K, [(P, '\'cd "$1" || exit 1; ( ./zn run', '\'cd "$1" && ( ./zn run')]),
 ("M4 net never writes its ready marker", K, [(W, 'fs.writeFile(ready, "ready\\n")', "local _ = ready")]),
 ("M5 early exit still exits 0", K, [(W, "before it had its worktree`}\\n`)\n\t\tgood = false", "before it had its worktree`}\\n`)\n\t\tgood = true")]),
 ("M6 net's error line on stdout, not stderr", K, [(W, "stdio.ewrite(`{last or `watch-net: the net exited ({code}) before it had its worktree`}\\n`)", "print(`{last or `watch-net: the net exited ({code}) before it had its worktree`}`)")]),
 ("M7 error line is the log's first line", K, [(M, "\t\t\tlast = line\n", "\t\t\tlast = last or line\n")]),
 ("M8 plain folder at the path: fail text silenced", K, [(W, "fail(`watch-net: {WT} exists and is not a worktree`)", 'fail("watch-net: stop")')]),
 ("M9 stale pass date taken from the author date", S, [(W, '"--format=%ct%x09%H%x09%s"', '"--format=%at%x09%H%x09%s"')]),
 ("M10 newest source taken by author date", S, [(W, '"--format=%x01%ct"', '"--format=%x01%at"')]),
 ("M11 newest compared as now, not main's newest source commit", S, [(W, "return watch.noPassLine(passed, newest, watchcmd", "return watch.noPassLine(passed, os.time(), watchcmd")]),
 ("M12 exactly at the limit counts as stale (<= to <)", S, [(M, "newest - passed <= limit", "newest - passed < limit")]),
 ("M13 date shown is the newest commit's, not the pass's", S, [(M, 'os.date("!%Y-%m-%d", passed)', 'os.date("!%Y-%m-%d", newest)')]),
 ("M14 line printed on stderr", S, [(W, "\t\tprint(line)\n\tend\n\treturn good", "\t\tstdio.ewrite(line .. \"\\n\")\n\tend\n\treturn good")]),
 ("M15 board does not show the line", S, [(B, "\treturn `<p class=\"note\" id=\"no-pass\">{text}</p>`", '\treturn ""')]),
 ("M16 board calls the pure rule with a limit of its own", S, [(B, 'local watchcmd = require("./watchcmd")', 'local watchcmd = require("./watchcmd")\nlocal watch = require("../lib/watch")'), (B, "facts.noPass = watchcmd.noPassLine(dir)", "facts.noPass = watch.noPassLine(nil, nil, 48 * 3600)")]),
 ("M17 board repeats the limit as the same literal", S, [(W, "function watchcmd.noPassLine(dir: string): string?", "function watchcmd.noPassLine(dir: string, limit: number?): string?"), (W, "return watch.noPassLine(passed, newest, watchcmd.NO_PASS_LIMIT_SECONDS)", "return watch.noPassLine(passed, newest, limit or watchcmd.NO_PASS_LIMIT_SECONDS)"), (B, "watchcmd.noPassLine(dir)", "watchcmd.noPassLine(dir, 86400)")]),
 ("N1 ready marker passed by environment again", K, [(P, "( ./zn run --time 3600 -- ./zn watch-net --ready \"$3\" --start \"$5\"", "( PICKMAN_WATCH_NET_READY=\"$3\" ./zn run --time 3600 -- ./zn watch-net --ready \"$3\" --start \"$5\"")]),
 ("N2 reaper exemption widened to any bash -c", R, [(P, "return string.sub(rest, 1, #prefix) == prefix", 'return string.sub(rest, 1, 3) == "-c "')]),
 ("N3 reaper exemption dropped", R, [(P, "\n\t\t\tor underNet(p, byPid)\n", "\n")]),
 ("N3b reaper exemption never expires", R, [(P, "or p.age > reap.NET_MAX_AGE then", "then")]),
 ("N4 lock not taken", L, [(W, "if held and watch.lockHeld(text, startOf(held.pid)) then", "if false and held then")]),
 ("N5 lock never released", L, [(W, "\t\tif fs.isFile(`{dir}/lock`) and fs.readFile(`{dir}/lock`) == mine then\n\t\t\tfs.removeFile(`{dir}/lock`)\n\t\tend\n\t\treturn false", "\t\treturn false")]),
 ("N6 rerun request ignored", L, [(M, "return requested and round < max", "return false")]),
 ("N7 rerun request honoured twice (not cleared)", L, [(W, "\t\tif requested then\n\t\t\tfs.removeFile(`{dir}/rerun`)\n\t\tend\n", "")]),
 ("N8 already-running net exits non-zero", L, [(W, '\t\tprint(`{watch.ALREADY} (pid {holder}); a rerun is requested`)\n\t\treturn', '\t\tprint(`{watch.ALREADY} (pid {holder}); a rerun is requested`)\n\t\tprocess.exit(1)')]),
 ("N8b kick treats already running as a failure", L, [(W, "\t\tand code == 0\n\t\tand last\n", "\t\tand code == 99\n\t\tand last\n")]),
 ("N9 backstop bound exits 0", K, [(W, "after {wait} s, log at {files.log}\\n`)\n\t\tgood = false", "after {wait} s, log at {files.log}\\n`)\n\t\tgood = true")]),
 ("N10 process-gone not detected", K, [(M, "elseif not alive then", "elseif false then")]),
 ("N11 shared file names again", K, [(M, 'string.format("%010d-%d", epoch, pid)', '"1-1"')]),
 ("N12 log in the kicking checkout", K, [(W, "local dir = watch.filesDir(main)\n\tfs.writeDir(`{main}/.cache`)", "local dir = watch.filesDir(root)\n\tfs.writeDir(`{root}/.cache`)")]),
 ("N13 tracker-only commits counted as newer", S, [(M, "elseif at ~= nil and not tracker(line) then", "elseif at ~= nil then")]),
 ("N14 source commits not counted", S, [(M, "elseif at ~= nil and not tracker(line) then", "elseif at ~= nil and false then")]),
 ("N15 the net's own start bound not enforced", K, [(W, "\tif r.code == 124 then\n\t\tfail(", "\tif false then\n\t\tfail(")]),
 ("N16 old kicks' files never pruned", L, [(M, "\ttable.sort(out)\n\treturn out\nend\n\n-- The newest pass", "\treturn {}\nend\n\n-- The newest pass")]),
 ("N17 a dead holder's lock holds forever", L, [(M, "return lock ~= nil and liveStart ~= nil and liveStart == lock.start", "return lock ~= nil")]),
 ("N18 a reused pid still holds the lock", L, [(M, "return lock ~= nil and liveStart ~= nil and liveStart == lock.start", "return lock ~= nil and liveStart ~= nil")]),
 ("N19 limit constant is 48 h", S, [(W, "watchcmd.NO_PASS_LIMIT_SECONDS = 24 * 3600", "watchcmd.NO_PASS_LIMIT_SECONDS = 48 * 3600")]),
]

def sh(argv, cwd):
    r = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr

for name, spec, edits in MUTANTS:
    if only and name.split()[0] not in only:
        continue
    saved = {}
    try:
        for f, old, new in edits:
            p = os.path.join(Z, f)
            if p not in saved:
                saved[p] = open(p).read()
            text = open(p).read()
            if text.count(old) != 1:
                print(f"{name}: {old!r} occurs {text.count(old)} times in {f}")
                if check_only:
                    continue
                raise SystemExit(1)
            if not check_only:
                open(p, "w").write(text.replace(old, new))
        if check_only:
            continue
        code, text = sh(["lune", "run", "tests/run", "--", spec], Z)
        fails = [l.split(" :: ", 1)[1] for l in text.splitlines() if l.startswith("FAIL ") and " :: " in l]
        with open(out, "a") as fh:
            fh.write(f"{name}\t{spec.split('/')[-1]}\t{'KILLED' if code != 0 else 'SURVIVED'}\t{len(fails)} failing\t{' | '.join(fails)}\n")
    finally:
        for p, t in saved.items():
            open(p, "w").write(t)
print("checked" if check_only else open(out).read())
