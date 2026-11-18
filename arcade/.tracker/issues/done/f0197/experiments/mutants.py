# f0197 mutation check. Run from anywhere in the repository, bounded:
#   ./zn run --time 1800 -- python3 arcade/.tracker/issues/f0197/experiments/mutants.py [M1 M2 ...]
# It never edits a checkout: it makes a fresh directory under the system temp folder (refusing one inside the
# repository), clones the repository there (`git clone --shared`, read-only use of the source), checks out BASE,
# applies prototype.patch beside this file, and copies in f0197's acceptance specs (the item folder before `./zn done`,
# arcade/tests/acceptance/f0197 after it). Each mutant is one exact text replacement in that clone; every f0197
# acceptance spec and the three unit specs then run from the clone's arcade/ through its own `./zn run --time`. The
# result is KILLED (a case failed on an assertion), SURVIVED, LOAD-ERROR (a spec could not load: the mutant is broken)
# or SKIP (its text is not in the source exactly once). The source is restored after each mutant, a SIGTERM becomes
# SystemExit so cleanup always runs, and the temporary directory is removed by its validated path at the end.
# Results recorded in mutants.txt.
import os
import shutil
import signal
import subprocess
import sys
import tempfile

BASE = "3290615a"
HERE = os.path.dirname(os.path.abspath(__file__))
ITEM = os.path.dirname(HERE)

LOGIC = "arcade/src/shared/Logic/Hiscores/init.luau"
BOARDS = "arcade/src/server/Boards.luau"
GAMES = "arcade/src/shared/HiscoreGames.luau"

# (id and name, file, exact old text, new text)
MUTANTS = [
    ("M1 commit drops revives", LOGIC, "\t\trevives = attempt.revives or 0,\n\t\trun = if named", "\t\trun = if named"),
    ("M2 valid ignores revives", LOGIC, "\t\tand (attempt.revives == nil or", "\t\tand (true or attempt.revives == nil or"),
    ("M3 fewer revives replace a tie", LOGIC,
     "attempt.score > stored.score or (attempt.score == stored.score and attempt.level > stored.level)",
     "attempt.score > stored.score or (attempt.score == stored.score and attempt.level > stored.level) or (attempt.score == stored.score and attempt.level == stored.level and (attempt.revives or 0) < (stored.revives or 0))"),
    ("M4a rows rank fewer revives first", LOGIC,
     "\t\telseif a.level ~= b.level then\n\t\t\treturn a.level > b.level\n\t\tend\n\t\treturn a.userId < b.userId",
     "\t\telseif a.level ~= b.level then\n\t\t\treturn a.level > b.level\n\t\telseif a.revives ~= b.revives then\n\t\t\treturn a.revives < b.revives\n\t\tend\n\t\treturn a.userId < b.userId"),
    ("M4b rows rank more revives first", LOGIC,
     "\t\telseif a.level ~= b.level then\n\t\t\treturn a.level > b.level\n\t\tend\n\t\treturn a.userId < b.userId",
     "\t\telseif a.level ~= b.level then\n\t\t\treturn a.level > b.level\n\t\telseif a.revives ~= b.revives then\n\t\t\treturn a.revives > b.revives\n\t\tend\n\t\treturn a.userId < b.userId"),
    ("M4c list ranks fewer revives first", LOGIC, "\telseif a.at ~= b.at then\n\t\treturn a.at < b.at",
     "\telseif a.revives ~= b.revives then\n\t\treturn a.revives < b.revives\n\telseif a.at ~= b.at then\n\t\treturn a.at < b.at"),
    ("M4d list ranks more revives first", LOGIC, "\telseif a.at ~= b.at then\n\t\treturn a.at < b.at",
     "\telseif a.revives ~= b.revives then\n\t\treturn a.revives > b.revives\n\telseif a.at ~= b.at then\n\t\treturn a.at < b.at"),
    ("M5 rows pass raw revives", LOGIC, "\t\t\t\t\trevives = Hiscores.revivesOf(companion.revives),",
     "\t\t\t\t\trevives = companion.revives or 0,"),
    ("M6 boardRows drops revives", LOGIC, "level = row.level, revives = row.revives }", "level = row.level } :: any"),
    ("M7 the list's reader drops revives", LOGIC, "\t\t\t\trevives = Hiscores.revivesOf(e.revives),", "\t\t\t\trevives = 0,"),
    ("M8 topRun writes 0", LOGIC, "\t\trevives = attempt.revives or 0,\n\t\tat = unix,", "\t\trevives = 0,\n\t\tat = unix,"),
    ("M9 bestRun's unnamed branch writes 0", LOGIC, "\t\trevives = Hiscores.revivesOf(row.revives),\n\t\tat = 0,",
     "\t\trevives = 0,\n\t\tat = 0,"),
    ("M9b bestRun's named branch writes 0", LOGIC, "\t\t\trevives = Hiscores.revivesOf(row.revives),\n\t\t\tat = row.at",
     "\t\t\trevives = 0,\n\t\t\tat = row.at"),
    ("M10 best writes 0", LOGIC, "\t\tlevel = companion.level,\n\t\trevives = Hiscores.revivesOf(companion.revives),",
     "\t\tlevel = companion.level,\n\t\trevives = 0,"),
    ("M11 onStep writes 0", LOGIC, "revives = if event.revives == nil then 0 else event.revives,", "revives = 0,"),
    ("M12 names no validation", LOGIC, "\tif\n\t\ttype(prefix) ~= \"string\"\n\t\tor #prefix > Hiscores.PREFIX_MAX",
     "\tif\n\t\tfalse and #prefix > Hiscores.PREFIX_MAX"),
    ("M13 names allow a lower-case start", LOGIC, 'string.match(prefix, "^%u[%a%d]*$")', 'string.match(prefix, "^%a[%a%d]*$")'),
    ("M14 names cap off by one", LOGIC, "\t\tor #prefix > Hiscores.PREFIX_MAX", "\t\tor #prefix >= Hiscores.PREFIX_MAX"),
    ("M15 names not frozen", LOGIC, "\treturn table.freeze({\n\t\tordered = `{prefix}Hiscores`,",
     "\treturn ({\n\t\tordered = `{prefix}Hiscores`,"),
    ("M16 storeTarget ignores the names", LOGIC,
     'local base = if kind == "ordered" then names.ordered else names.companion',
     'local base = if kind == "ordered" then "Hiscores" else "HiscoreEntries"'),
    ("M17 Snake shares pickman's prefix", GAMES, 'prefix = "Snake",', 'prefix = "",'),
    ("M18 open makes a new handle each call", BOARDS, "\tlocal found = games[names.ordered]", "\tlocal found = nil"),
    ("M19 the list store hard-coded", BOARDS, "GetDataStore(names.top, Hiscores.TOP_SCOPE)",
     'GetDataStore("HiscoreTop", Hiscores.TOP_SCOPE)'),
    ("M20 submit drops revives", BOARDS, "score = score, revives = revives }", "score = score }"),
    ("M21 a failed read sent as healthy", BOARDS, "reply(waiter, id, rows or before, rows == nil)",
     "reply(waiter, id, rows or before, false)"),
    ("M22 titles share one cache", BOARDS, "\tlocal keys: { [string]: KeyState } = {}",
     "\tlocal keys: { [string]: KeyState } = (Boards :: any).shared or {}\n\t;(Boards :: any).shared = keys"),
    ("M23 a leaving player's best kept", BOARDS, "\t\t\t\t\tbests[tostring(player.UserId)] = nil", "\t\t\t\t\tlocal _ = player"),
    ("M24 one pending count for every handle", BOARDS, "\tlocal pending = 0\n",
     "\tlocal pending = 0\n\tlocal _ = pending\n"),  # replaced by SPECIAL below
    ("M25 the best sent with every board", BOARDS, 'local held = if id == "all" then bests[tostring(player.UserId)] else nil',
     "local held = bests[tostring(player.UserId)]"),
    ("M26 raw rows sent", BOARDS, "\t\t\t\t\tHiscores.boardRows(rows),", "\t\t\t\t\trows,"),
    ("M27 no page-of-50 fallback in Logic", LOGIC, "\telseif n == 2 then\n\t\treturn 50", "\telseif n == 2 then\n\t\treturn nil"),
    ("M28 pickman's window one short", LOGIC, "Hiscores.LEAVE_STEPS = 45", "Hiscores.LEAVE_STEPS = 44"),
    ("M29 day key in local time", LOGIC, "\treturn unix // SECONDS_PER_DAY", "\treturn (unix - 8 * 3600) // SECONDS_PER_DAY"),
    ("M30 the ordered write not a max", LOGIC, "return math.max(old or 0, Hiscores.pack(row.score, row.level))",
     "return Hiscores.pack(row.score, row.level)"),
    ("M31 leave ignores its window", LOGIC, "if sawOver or stepsWaited >= window then",
     "if sawOver or stepsWaited >= Hiscores.LEAVE_STEPS then"),
    ("M32 onStep ignores its window", LOGIC, "Hiscores.leave(waited, saw, window)", "Hiscores.leave(waited, saw, Hiscores.LEAVE_STEPS)"),
    ("M33 the list's reader passes junk revives", LOGIC, "\t\t\t\trevives = Hiscores.revivesOf(e.revives),",
     "\t\t\t\trevives = e.revives or 0,"),
    ("M34 best passes junk revives", LOGIC, "\t\trevives = Hiscores.revivesOf(companion.revives),\n\t}",
     "\t\trevives = companion.revives or 0,\n\t}"),
    ("M35 valid has no revives bound", LOGIC, "and attempt.revives >= 0 and attempt.revives <= MAX_INTEGER))",
     "and attempt.revives >= 0))"),
    ("M36 revivesOf has no bound", LOGIC, "if whole(raw) and raw >= 0 and raw <= MAX_INTEGER then", "if whole(raw) and raw >= 0 then"),
    ("M37 one listener for every handle", BOARDS, "\tlocal listener: Listener? = nil\n", ""),  # SPECIAL below
    ("M39 (X4) no list fails the all-time read", BOARDS, "\t\t\t\tif listed ~= nil then\n\t\t\t\t\treturn listed\n\t\t\t\tend",
     "\t\t\t\tif listed ~= nil then\n\t\t\t\t\treturn listed\n\t\t\t\tend\n\t\t\t\terror(\"no list\", 0)"),
    ("M40 (Y1) no size-50 retry", BOARDS, "\t\tfor attempt = 1, 2 do", "\t\tfor attempt = 1, 1 do"),
    ("M41 (Y2) an unreadable row skipped", BOARDS, "\t\t\t\treturn io.get(board, key)",
     "\t\t\t\tlocal got, err = io.get(board, key)\n\t\t\t\tif err ~= nil then\n\t\t\t\t\treturn nil, nil\n\t\t\t\tend\n\t\t\t\treturn got, nil"),
    ("M42 (Y3) a request during a read never answered", BOARDS,
     "\t\t\t\telseif state.inflight then\n\t\t\t\t\ttable.insert(state.waiters, player)",
     "\t\t\t\telseif state.inflight then\n\t\t\t\t\tlocal _ = player"),
    ("M43 (Y4) the failure wait ignored", BOARDS, "\t\t\t\t\tstate.failure\n\t\t\t\t)", "\t\t\t\t\tnil\n\t\t\t\t)"),
    ("M44 (Y5) the get budget is OrderedRead", BOARDS, "\tget = Enum.DataStoreRequestType.StandardRead,",
     "\tget = Enum.DataStoreRequestType.OrderedRead,"),
    ("M45 (Y6) a departed player answered", BOARDS, "\t\t\t\tif player.Parent == nil then\n\t\t\t\t\treturn\n\t\t\t\tend\n",
     ""),
    ("M46 (Y7) pending kept when the write throws", BOARDS,
     "\t\t\t\tif not fine then\n\t\t\t\t\twarn(`[arcade] hiscore write failed ({names.ordered}): {failure}`)\n\t\t\t\tend\n\t\t\t\tpending -= 1",
     "\t\t\t\tif not fine then\n\t\t\t\t\twarn(`[arcade] hiscore write failed ({names.ordered}): {failure}`)\n\t\t\t\telse\n\t\t\t\t\tpending -= 1\n\t\t\t\tend"),
    ("M47 (Y8) a failed read answers empty rows", BOARDS, "reply(waiter, id, rows or before, rows == nil)",
     "reply(waiter, id, rows or {}, rows == nil)"),
    ("M48 (Y9) a stale best kept when its re-read fails", BOARDS,
     "best = if err == nil then Hiscores.best(got) else nil,", "best = if err == nil then Hiscores.best(got) else mark.best,"),
    ("M49 (Y10) a best read after the player left kept", BOARDS,
     "if bests[userId] == mark and player.Parent ~= nil then", "if bests[userId] == mark then"),
    ("M50 (Y11) the budgets never asked", BOARDS,
     "\t\t\treturn DataStoreService:GetRequestBudgetForRequestType(BUDGETS[op])", "\t\t\treturn 100"),
    ("M38 a refused run is silent", BOARDS, "\t\t\t\t\t\twarn(`[arcade] hiscore run refused ({names.ordered})`)",
     "\t\t\t\t\t\tlocal _ = names"),
]

# mutants that need more than one replacement: (id) -> list of (old, new) applied after the main one
SPECIAL = {
    "M24": [("local games: { [string]: Game } = {}", "local games: { [string]: Game } = {}\nlocal pending = 0")],
    "M37": [("local games: { [string]: Game } = {}", "local games: { [string]: Game } = {}\nlocal listener: Listener? = nil")],
}
# M24's main replacement removes the per-handle count instead of shadowing it
MAIN_OVERRIDE = {"M24": ("\tlocal pending = 0\n", "")}

UNITS = ["tests/unit/Hiscores/hiscores.spec.luau", "tests/unit/Hiscores/read.spec.luau", "tests/unit/Hiscores/run.spec.luau"]


def sh(args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True)


def stop(*_):
    raise SystemExit(143)


def main():
    signal.signal(signal.SIGTERM, stop)
    repo = sh(["git", "rev-parse", "--show-toplevel"], cwd=HERE).stdout.strip()
    acceptance = os.path.join(ITEM, "acceptance")
    if not os.path.isdir(acceptance):
        acceptance = os.path.join(repo, "arcade", "tests", "acceptance", "f0197")
    tmp_root = os.path.realpath(tempfile.gettempdir())
    if os.path.realpath(tmp_root).startswith(os.path.realpath(repo) + os.sep):
        sys.exit("mutants: the temp folder is inside the repository; refusing")
    work = tempfile.mkdtemp(prefix="f0197-mutants-", dir=tmp_root)
    try:
        clone = os.path.join(work, "repo")
        for args in (
            ["git", "clone", "-q", "--shared", "--no-checkout", repo, clone],
            ["git", "-C", clone, "checkout", "-q", BASE],
            ["git", "-C", clone, "apply", os.path.join(HERE, "prototype.patch")],
        ):
            r = sh(args)
            if r.returncode != 0:
                sys.exit(f"mutants: {' '.join(args[:3])} failed: {r.stderr.strip()}")
        dest = os.path.join(clone, "arcade", ".tracker", "issues", "f0197", "acceptance")
        shutil.rmtree(dest, ignore_errors=True)
        shutil.copytree(acceptance, dest)
        specs = sorted(
            os.path.join(".tracker/issues/f0197/acceptance", f) for f in os.listdir(dest) if f.endswith(".spec.luau")
        ) + UNITS
        home = os.path.join(clone, "arcade")
        only = sys.argv[1:]
        for name, rel, old, new in MUTANTS:
            mid = name.split(" ")[0]
            if only and mid not in only:
                continue
            path = os.path.join(clone, rel)
            src = open(path).read()
            if mid in MAIN_OVERRIDE:
                old, new = MAIN_OVERRIDE[mid]
            if src.count(old) != 1:
                print(f"{name}: SKIP (its text is in the source {src.count(old)} times)", flush=True)
                continue
            mutated = src.replace(old, new)
            for o, n in SPECIAL.get(mid, []):
                mutated = mutated.replace(o, n, 1)
            try:
                open(path, "w").write(mutated)
                r = sh(["../zn", "run", "--time", "300", "--", "lune", "run", "tests/run", "--"] + specs, cwd=home)
                out = (r.stdout + r.stderr).splitlines()
                load = [l for l in out if "could not load spec" in l]
                fails = [l.split(" :: ", 1)[1] for l in out if l.startswith("FAIL") and " :: " in l]
                if load:
                    verdict = "LOAD-ERROR"
                elif fails:
                    verdict = "KILLED"
                else:
                    verdict = "SURVIVED"
                print(f"{name}: {verdict}" + (f" by {fails[0]}" if fails else ""), flush=True)
            finally:
                open(path, "w").write(src)
    finally:
        real = os.path.realpath(work)
        if real.startswith(tmp_root + os.sep) and os.path.basename(real).startswith("f0197-mutants-"):
            shutil.rmtree(real, ignore_errors=True)


if __name__ == "__main__":
    main()
