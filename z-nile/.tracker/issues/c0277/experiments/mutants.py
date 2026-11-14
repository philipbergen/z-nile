#!/usr/bin/env python3
"""c0277 mutation check. Applies each mutant to a scratch worktree of proto-c0277, runs the row's spec files, expects a
failing assertion (not a load error), and reverts. Run: ./zn run --time 3500 -- python3 mutants.py <scratch-worktree> [id ...]
"""
import subprocess, sys, os, re

WT = sys.argv[1]
ONLY = set(sys.argv[2:])
HB = "z-nile/engine/heartbeat.luau"
MAIN = "z-nile/engine/main.luau"
DISP = "z-nile/engine/dispatcher.luau"
A = "tests/acceptance/c0277/"
PLAN, DISCARD, RECOVER, GUARD, SWEEP, PROOF, REREADY = (A + "plan.spec.luau", A + "discard.spec.luau", A + "recover.spec.luau",
                                               A + "guard.spec.luau", A + "sweep.spec.luau", A + "proofs/discard.spec.luau", A + "reready.spec.luau")

# (id, file, [(old, new)], [specs])
M = []
def m(i, f, pairs, specs):
    if isinstance(pairs, tuple):
        pairs = [pairs]
    M.append((i, f, pairs, specs))

# --- pure rules (heartbeat.luau) -> plan.spec
m("P1", HB, ("while used[n] do\n\t\tn += 1", "while used[n] do\n\t\tn += 2"), [PLAN])
m("P2", HB, ("\t\tif n then\n\t\t\tused[n] = true", "\t\tif n then\n\t\t\tused[n] = false"), [PLAN])
m("P3", HB, ("if n and n >= 1 and tostring(n) == digits then", "if n and n >= 1 then"), [PLAN])
m("P4", HB, ("if n and n >= 1 and tostring(n) == digits then", "if n and n >= 0 and tostring(n) == digits then"), [PLAN])
m("P5", HB, ('"^" .. string.gsub(base, "%p", "%%%0") .. "%-(%d+)$"', '"^" .. base .. "%-(%d+)$"'), [PLAN])
m("P6", HB, ("if n and not discarded[name] and n > bestN then", "if n and not discarded[name] and (best == nil or n < bestN) then"), [PLAN])
m("P7", HB, ("if n and not discarded[name] and n > bestN then", "if n and n > bestN then"), [PLAN])
m("P8", HB, ("\tif raft then\n\t\treturn raft\n", "\tif false then\n\t\treturn raft\n"), [PLAN])
m("P9", HB, ('return (string.gsub(dirName, "%-%d+$", ""))', "return dirName"), [PLAN])
m("P10", HB, ("return epoch ~= nil and now - epoch < limit", "return epoch ~= nil and now - epoch <= limit"), [PLAN])
m("P11", HB, ("return epoch ~= nil and now - epoch < limit", "return epoch == nil or now - epoch < limit"), [PLAN])
m("P12", HB, ('(slug ~= nil and (branch == `prep-{slug}` or branch == `raft-{slug}`))', '(slug ~= nil and (string.sub(branch, 1, 5) == "prep-" or branch == `raft-{slug}`))'), [PLAN])
m("P13", HB, ("\t\treturn id == raft or id == issue\n", "\t\treturn true\n"), [PLAN])
m("P14", HB, ('if not (v and heartbeat.canTakeOver(v.kind, v.stamp, f.current or "")) then', 'if not (v and v.kind == "lost") then'), [PLAN])
m("P15", HB, ('elseif held == "held" or held == "unheld" then', "elseif true then"), [PLAN])
m("P16", HB, ("\tif #facts == 0 then\n", "\tif false then\n"), [PLAN])
m("P17", HB, ('if f.remembered == "" and f.current == nil then', "if false then"), [PLAN])
m("P18", HB, ("local LIST_CAP = 20", "local LIST_CAP = 25"), [PLAN])
m("P19", HB, ("else `origin/main..{f.branch}`", "else `origin/{f.base}..{f.branch}`"), [PLAN])
m("P20", HB, ("if not (path and copy and branch and base and pushed and items and since) then", "if not (path and copy and branch and pushed and items and since) then"), [PLAN])
m("P21", HB, ('return "this worktree was discarded. Clear your context and pick up something new. " .. text', "return text"), [PLAN])
m("P22", HB, ("\t\tif live[id] == true then", "\t\tif live[id] == true and false then"), [PLAN])
m("P23", HB, ("elseif unreachable > 0 then\n\t\treturn `{unreachable} commit(s) exist nowhere else`", "elseif false then\n\t\treturn `{unreachable} commit(s) exist nowhere else`"), [PLAN])
m("P24", HB, ("elseif discarded == true then", "elseif false then"), [PLAN])

# --- engine (main.luau, dispatcher.luau)
m("E1", MAIN, ("local refusal = heartbeat.discardRefusal(facts, why)", "local refusal = nil :: string?"), [DISCARD])
m("E2", MAIN, ("if heartbeat.fresh(epoch, now, heartbeat.STALE) then", "if false then"), [DISCARD])
m("E3", MAIN, ("\tsh.writeReplacing(`{copyPath}/{hb.FRESH}`, tostring(now))\n", "\tlocal _ = 0\n"), [DISCARD])
m("E4", MAIN, ("if not hb.claimFile(marker, text) then", "if not true then"), [DISCARD, RECOVER])
m("E5", MAIN, ('local mv = sh.run("git", { "worktree", "move", old.path, discardedPath })', "local mv: any = { ok = true, stderr = '' }"), [DISCARD])
m("E6", MAIN, ('then sh.run("git", { "branch", "-m", oldBranch, renamed })', "then { ok = true, stderr = '', stdout = '', code = 0 } :: any"), [DISCARD])
m("E7", MAIN, ('\t\t\tsh.run("git", { "branch", "--unset-upstream", renamed })\n', "\t\t\tlocal _ = 0\n"), [DISCARD])
m("E8", MAIN, ("pcall(hb.addWorktree, copyPath, branch, detach, mainRef)", "pcall(hb.addWorktree, copyPath, nil, true, mainRef)"), [DISCARD, RECOVER])
m("E9", MAIN, ("\t\t\t\tif fs.isFile(`{d}/{f}`) then\n\t\t\t\t\tfs.removeFile(`{d}/{f}`)", "\t\t\t\tif false then\n\t\t\t\t\tfs.removeFile(`{d}/{f}`)"), [RECOVER])
m("E10", MAIN, ("\t\ttable.insert(dirty, string.sub(line, 4))", "\t\tlocal _ = line"), [RECOVER])
m("E11", MAIN, ("local unpushed = hb.logLines(old.path, `{if up then `origin/{oldBranch}` else mainRef}..HEAD`)", "local unpushed = hb.logLines(old.path, `{mainRef}..HEAD`)"), [RECOVER])
m("E12", MAIN, ("elseif #unpushed > 0 then `discarded-{family0}-{number}`", "elseif false then `discarded-{family0}-{number}`"), [RECOVER])
m("E13", MAIN, ("pushed = if up then hb.logLines(old.path, `{mainRef}..origin/{oldBranch}`) else {},", "pushed = {},"), [RECOVER])
m("E14", MAIN, [("\thb.refuseDiscarded(name :: string) -- c0277: a discarded worktree refuses every command but reap (before anything beats)\n\tguardRepoRoot()", "\tguardRepoRoot()"),
                ("hb.begin(name :: string, READ_ONLY[name :: string] == true)", "hb.begin(name :: string, READ_ONLY[name :: string] == true)\nif not READ_ONLY[name :: string] then\n\thb.refuseDiscarded(name :: string)\nend")], [GUARD])
m("E15", MAIN, ('if name == "reap" or not fs.isFile(hb.DISCARDED) then', "if not fs.isFile(hb.DISCARDED) then"), [GUARD])
m("E16", MAIN, [("if not READ_ONLY[name :: string] then\n\thb.refuseDiscarded(name :: string)", "hb.refuseDiscarded(name :: string)\nif not READ_ONLY[name :: string] then\n\tlocal _ = 0")], [GUARD])
m("E17", MAIN, ("local live = heartbeat.currentOf(dirName, names, discarded)", "local live = if #names > 0 then dirName else nil"), [DISCARD, RECOVER])
m("E18", MAIN, ("\tif #taken > 0 then\n\t\tname = heartbeat.nextSuffix(dirName, hb.takenNames(dirName))", "\tif false then\n\t\tname = heartbeat.nextSuffix(dirName, hb.takenNames(dirName))"), [DISCARD])
m("E19", MAIN, ('if d and d.base ~= "" then', "if false then"), [DISCARD])
m("E20", MAIN, ("local copyName = heartbeat.nextSuffix(family0, hb.takenNames(family0))", 'local copyName = family0 .. "-1"'), [DISCARD])
m("E21", MAIN, ('if mem ~= "" and mem == origin then', 'if mem ~= "" then'), [DISCARD])
m("E22", MAIN, ("\tif fs.isFile(heartbeat.FRESH) then\n\t\tfs.removeFile(heartbeat.FRESH)", "\tif false then\n\t\tfs.removeFile(heartbeat.FRESH)"), [DISCARD])
m("E23", MAIN, ("if not heartbeat.discardEnded(live, d.items) then", "if false then"), [SWEEP])
m("E24", MAIN, ("local why = heartbeat.keepReason(dirty, unreachable)", "local why = heartbeat.keepReason(0, unreachable)"), [SWEEP])
m("E25", MAIN, ("local why = heartbeat.keepReason(dirty, unreachable)", "local why = heartbeat.keepReason(dirty, 0)"), [SWEEP])
m("E26", MAIN, ('string.match(name, "^(R%d%d%d%d)%-%d+$") or name -- c0277: R0010-1 is R0010\'s copy', "name -- mutant"), [SWEEP])
m("E27", MAIN, ('if opts["--session-end"] == nil and opts["--quiet"] == nil and not guarded(true) then', "if not guarded(true) then"), [SWEEP])
m("E28", MAIN, ("\t\t\tlocal swept, r = pcall(hb.sweepDiscarded, true)\n", "\t\t\tlocal swept, r = false, nil\n"), [SWEEP])
m("E29", MAIN, ("\tif id then\n\t\tadd(id)\n\tend", "\tif false then\n\t\tadd(id :: string)\n\tend"), [DISCARD])
m("E30", MAIN, ("if not heartbeat.ownsBranch(old.branch, item, it.slug) then", "if false then"), [DISCARD])
m("E31", MAIN, ("\t\t\tthere and fs.isFile(`{home}/{hb.DISCARDED}`) -- c0277: a takeover discarded this worktree", "\t\t\tfalse"), [PROOF])
m("E32", DISP, ("if not fs.isDir(cwd) or fs.isFile(`{cwd}/{heartbeat.DISCARDED}`) then", "if false then"), [PROOF])
m("E33", MAIN, ('\t\t\t\tthen sh.run("git", { "branch", "-m", renamed, oldBranch })', '\t\t\t\tthen { ok = true, stderr = "", stdout = "", code = 0 } :: any'), [DISCARD])
m("E34", MAIN, ("\t\tpcall(fs.removeFile, marker)\n\t\treturn fail(msg)", "\t\treturn fail(msg)"), [DISCARD])
m("E35", MAIN, ("local verdicts, why = hb.judgedFor(paths :: { string })", "local verdicts, why = hb.judgedFor(paths :: { string })\n\twhy = nil"), [DISCARD])

m("E37", MAIN, ('if sh.trim(sh.run("git", { "rev-parse", "--show-toplevel" }).stdout) == old.path then', "if false then"), [DISCARD])

m("E38", MAIN, ("\t\tif branch and w.branch == branch then\n\t\t\tfail(`{branch} is already used by worktree at {w.path}`)", "\t\tif false then\n\t\t\tfail(`{branch} is already used by worktree at {w.path}`)"), [DISCARD])
m("E40", MAIN, ('\t\t\t\tor string.match(name, "^tracker%-claim%-(.+)$")', '\t\t\t\tor nil'), [DISCARD])

m("E41", MAIN, ('local r = sh.run("ln", { tmp, path })', 'local r = sh.run("ln", { "-f", tmp, path })'), [DISCARD])

m("P25", HB, ("\treturn branch == base\nend", "\treturn true\nend"), [PLAN])
m("P26", HB, ("\t\treturn branch == nil or branch == \"\" or layer == base", "\t\treturn true"), [PLAN])
m("E43", MAIN, ("\t\t\t\tand w.discarded\n", "\t\t\t\tand false\n"), [DISCARD])
m("E44", MAIN, ("\t\t\t\tand string.match(w.name, \"^\" .. string.gsub(dirName, \"%p\", \"%%%0\") .. \"%-discarded%-%d+$\")", "\t\t\t\tand false"), [DISCARD])
m("E45", MAIN, ("\tif not statusRead.ok then", "\tif false then"), [DISCARD])
m("E46", MAIN, ("\t\tif moved and not sh.run(", "\t\tif false and not sh.run("), [DISCARD])
m("E47", MAIN, ("\t\tfor _, name in fs.readDir(wt) do\n\t\t\ttable.insert(out, name)\n\t\tend", "\t\tfor _, name in fs.readDir(wt) do\n\t\t\tlocal _ = name\n\t\tend"), [DISCARD])
m("E48", MAIN, ("\tif commits > 0 then", "\tif false then"), [SWEEP])
m("E49", MAIN, ("\t\t\tif not (inMain.ok and mine.ok and sh.trim(mine.stdout) == sh.trim(inMain.stdout)) then", "\t\t\tif false then"), [SWEEP])
m("E50", MAIN, ('{ "worktree", "remove", "--force", w.path }', '{ "worktree", "remove", w.path }'), [SWEEP])
m("E51", DISP, ("\t\t\t\tif onDiscard then", "\t\t\t\tif false then"), [PROOF])
m("E52", MAIN, ("elseif #unpushed > 0 then `discarded-{family0}-{number}`", "elseif #unpushed > 0 then `{family0}-discarded-{number}`"), [RECOVER])
m("E53", MAIN, ("\t-- c0277: the raft is given back: the worktrees discarded for it go (unless they still hold unrecovered work)\n\tlocal swept, sweep = pcall(hb.sweepDiscarded, true)", "\tlocal swept, sweep = false, nil"), [SWEEP])
m("E54", MAIN, ("\t\tlocal merged = sh.run(\"git\", mergeArgs)", "\t\tlocal merged = { ok = false, stdout = '' } :: any"), [SWEEP])

m("E55", MAIN, ("live[id] = paths == nil or hb.claimStampOf(paths, id) ~= nil", "live[id] = paths ~= nil and hb.claimStampOf(paths, id) ~= nil"), [SWEEP])

m("P27", HB, ('\t\tif held == "held" then\n\t\t\treturn false', '\t\tif false then\n\t\t\treturn false'), [PLAN])
m("P28", HB, ('elseif held == "taken" or held == "ended" then\n\t\t\tover = true', 'elseif held == "taken" then\n\t\t\tover = true'), [PLAN])
m("E56", MAIN, ("if heartbeat.staleMember(facts) then", "if false then"), [REREADY, PROOF])
m("E57", MAIN, ("\t\t\tlocal paths = hb.beatPaths()\n\t\t\tif paths then\n\t\t\t\tlocal facts: { heartbeat.ClaimFact } = {}", "\t\t\tlocal paths = hb.beatPaths() or {}\n\t\t\tif true then\n\t\t\t\tlocal facts: { heartbeat.ClaimFact } = {}"), [REREADY])
m("E58", MAIN, ("\t\tif member and #ids > 0 then", "\t\tif false then"), [REREADY])

def run(cmd, cwd, timeout):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout + r.stderr

TOP = os.path.abspath(os.path.join(WT, "..", ".."))
PINS = [("origin/prep-work-heartbeat", "z-nile/.tracker/issues/c0265/acceptance", "z-nile/tests/acceptance/c0265"),
        ("origin/prep-take-over-lost-claim", "z-nile/.tracker/issues/c0274/acceptance", "z-nile/tests/acceptance/c0274"),
        ("origin/prep-automatic-heartbeats", "z-nile/.tracker/issues/c0275/acceptance", "z-nile/tests/acceptance/c0275")]

def preflight():
    """The base pins what it was cut from: refuse when a prep's promoted specs differ from the prototype's copies, or when
    the prototype is not on the unmutated base."""
    bad = []
    for (br, src, dst) in PINS:
        lst = subprocess.run(["git", "-C", TOP, "ls-tree", "-r", "--name-only", br, "--", src], capture_output=True, text=True).stdout.split()
        for f in lst:
            rel = f[len(src) + 1:]
            if rel.endswith("watch.txt"):
                continue
            want = subprocess.run(["git", "-C", TOP, "rev-parse", f"{br}:{f}"], capture_output=True, text=True).stdout.strip()
            have = subprocess.run(["git", "hash-object", os.path.join(WT, dst, rel)], capture_output=True, text=True).stdout.strip()
            if want != have:
                bad.append(f"{br}:{f}")
    if bad:
        print("REFUSED: the base moved; a prep's promoted specs differ from the prototype's copies:", *bad, sep="\n  ")
        sys.exit(2)
    code, out = run([os.path.join(WT, "zn"), "run", "--time", "900", "--", "lune", "run", "tests/run", "--", PLAN, DISCARD, RECOVER, GUARD, SWEEP, PROOF, REREADY,
                     "tests/acceptance/c0265/heartbeat.spec.luau", "tests/acceptance/c0274/plan.spec.luau", "tests/acceptance/c0275/plan.spec.luau",
                     "tests/acceptance/c0275/reap.spec.luau"], os.path.join(WT, "z-nile"), 1000)
    tail = out.strip().splitlines()[-1] if out.strip() else ""
    print("unmutated base:", tail, flush=True)
    if code != 0:
        print(out)
        sys.exit(3)

def main():
    preflight()
    results = []
    for (i, f, pairs, specs) in M:
        if ONLY and i not in ONLY:
            continue
        path = os.path.join(WT, f)
        orig = open(path).read()
        mutated = orig
        ok = True
        for (old, new) in pairs:
            if old not in mutated:
                ok = False
                break
            mutated = mutated.replace(old, new, 1)
        if ok:
            for (old, new) in pairs:
                if orig.count(old) != 1:
                    ok = False
                    break
        if not ok:
            results.append((i, "NOT-APPLIED", "pattern absent or not unique"))
            print(i, "NOT-APPLIED", flush=True)
            continue
        open(path, "w").write(mutated)
        try:
            code, out = run([os.path.join(WT, "zn"), "run", "--time", "420", "--", "lune", "run", "tests/run", "--"] + specs,
                            os.path.join(WT, "z-nile"), 480)
        finally:
            open(path, "w").write(orig)
        fails = [l for l in out.splitlines() if l.startswith("FAIL") and "::" in l]
        bad = [l for l in out.splitlines() if "could not load" in l or "SyntaxError" in l or "Syntax error" in l]
        if bad:
            status = "LOAD-ERROR"
        elif fails:
            status = "KILLED"
        else:
            status = "SURVIVED"
        first = (fails[0] if fails else (bad[0] if bad else out.strip().splitlines()[-1] if out.strip() else ""))[:200]
        results.append((i, status, first))
        print(i, status, first, flush=True)
    print("\nSUMMARY")
    for r in results:
        print(*r)

main()
