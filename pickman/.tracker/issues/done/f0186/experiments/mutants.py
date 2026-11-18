#!/usr/bin/env python3
"""f0186 mutation check (prep). Never edits a checkout: it makes a fresh `mktemp -d`, clones the repository there
(`git clone --shared --no-checkout`, read-only on the source), checks out BASE, applies prototype.patch, copies this
issue's acceptance specs into the clone's pickman/tests/acceptance/f0186, and for each mutant: applies it, runs the
row's spec through the clone's own `./zn run --time 120`, checks that the row's case FAILS on an assertion (an
"expected ..." message, never a load or call error), and restores the file. The clone is removed on exit (SIGTERM
included). Run from anywhere:  ./zn run --time 1800 -- python3 <this file> [MUTANT_ID ...]
BASE is f0145's prototype (proto-f0145 at e396d79b6: its prep branch with f0147's, f0148's and f0145's prototypes)."""
import os, re, shutil, signal, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ISSUE = os.path.dirname(HERE)
SRC_REPO = subprocess.check_output(["git", "-C", HERE, "rev-parse", "--path-format=absolute", "--git-common-dir"], text=True).strip()
BASE = "e396d79b6"
H = "pickman/src/shared/Logic/Hiscores/init.luau"
L = "pickman/src/shared/Logic/Lobby/init.luau"
F = "pickman/src/shared/Logic/Flow/init.luau"
V = "pickman/src/client/RevivesView.luau"
M = "pickman/src/client/Main.client.luau"
S = "pickman/src/server/HiscoreStore.luau"
A = "tests/acceptance/f0186/"

# id, file, old, new, occurrence (1-based), spec, case substring
G = "pickman/src/shared/Logic/Game/init.luau"
SE = "pickman/src/shared/Logic/Session/init.luau"
SU = "pickman/src/server/Submits.luau"
TP = "pickman/src/shared/TestPurchase.luau"
PV = "pickman/src/lobby/client/PayView.luau"
GD = "pickman/.tracker/game-design.md"
AR = "pickman/.tracker/architecture.md"
MUTANTS = [
    ("G1", G, "\tg.revives += 1\n", "", 1, "count", "each continue the offer takes"),
    ("G2", G, "function Game.continue(g: Game, lives: number): ({ Event }, boolean)\n", "function Game.continue(g: Game, lives: number): ({ Event }, boolean)\n\tg.revives += 1\n", 1, "count", "a continue outside the offer"),
    ("G3", G, "\tg.lives, g.held, g.waiting = lives, false, 0\n\tg.revives += 1\n", "\tg.lives, g.held, g.waiting = lives, false, 0\n\tg.revives += lives\n", 1, "count", "each continue the offer takes"),
    ("G4", G, "\tg.lost, g.held, g.waiting, g.revives = 0, false, 0, 0\n", "\tg.lost, g.held, g.waiting = 0, false, 0\n", 1, "count", "a new run starts with none"),
    ("G5", G, "lives = g.lost, revives = g.revives },", "lives = g.lost },", 1, "count", "every game over carries"),
    ("G6", G, "\t\t\t\t\t\trevives = g.revives,\n", "", 1, "count", "every game over carries"),
    ("G7", G, "\tif g.phase ~= \"offer\" or not isWhole(lives) or lives < 1 then\n\t\treturn {}, false\n\tend\n\tg.lives, g.held, g.waiting = lives, false, 0\n\tg.revives += 1\n",
     "\tif g.phase ~= \"offer\" then\n\t\treturn {}, false\n\tend\n\tg.revives += 1\n\tif not isWhole(lives) or lives < 1 then\n\t\treturn {}, false\n\tend\n\tg.lives, g.held, g.waiting = lives, false, 0\n", 1, "count", "each continue the offer takes"),
    ("S1", SE, "\t\trevives = e.revives,\n\t}\nend", "\t}\nend", 1, "count", "a session's game over"),
    ("S2", SE, "\t\t\trevives = if play.revives > 0 then play.revives else nil,\n", "\t\t\trevives = play.revives,\n", 1, "count", "a session's game over"),
    ("S3", SE, "\t\t\trevives = if play.revives > 0 then play.revives else nil,\n", "", 1, "count", "a session's game over"),
    ("U1", SU, "\t\t\tsubmission.lives, -- f0145: the lives the run spent\n\t\t\tsubmission.revives -- f0186: the paid revives it used, nil for none\n", "\t\t\tsubmission.lives -- f0145: the lives the run spent\n", 1, "submit", "Submits hands HiscoreStore"),
    ("U2", SU, "\t\t\tsubmission.lives, -- f0145: the lives the run spent\n\t\t\tsubmission.revives -- f0186: the paid revives it used, nil for none\n", "\t\t\tsubmission.revives, -- swapped\n\t\t\tsubmission.lives\n", 1, "submit", "Submits hands HiscoreStore"),
    ("R1", H, "x >= 1 and x <= MAX_INTEGER", "x >= 0 and x <= MAX_INTEGER", 1, "rows", "Hiscores.revives keeps"),
    ("R2", H, "x >= 1 and x <= MAX_INTEGER", "x >= 1", 1, "rows", "Hiscores.revives keeps"),
    ("R3", H, "\t\tlives = Hiscores.lives(attempt.lives),\n\t\trevives = Hiscores.revives(attempt.revives),\n\t}\nend", "\t\tlives = Hiscores.lives(attempt.lives),\n\t}\nend", 1, "rows", "a stored row keeps"),
    ("R4", H, "\t\tlives = Hiscores.lives(attempt.lives),\n\t\trevives = Hiscores.revives(attempt.revives),\n\t}\nend", "\t\tlives = Hiscores.lives(attempt.lives),\n\t\trevives = Hiscores.revives(attempt.revives) or (if stored then stored.revives else nil),\n\t}\nend", 1, "rows", "replaces another"),
    ("R5", H, "\t\tlives = Hiscores.lives(attempt.lives),\n\t\trevives = Hiscores.revives(attempt.revives),\n\t}\nend", "\t\tlives = Hiscores.lives(attempt.lives),\n\t\trevives = attempt.revives,\n\t}\nend", 1, "rows", "broken stored or sent"),
    ("R6", H, "\t\t\t\t\trevives = Hiscores.revives(companion.revives),\n", "", 1, "rows", "a stored row keeps"),
    ("R7", H, "\t\t\t\t\trevives = Hiscores.revives(companion.revives),\n", "\t\t\t\t\trevives = companion.revives,\n", 1, "rows", "broken stored or sent"),
    ("R8", H, "\t\t\tlives = row.lives,\n\t\t\trevives = row.revives,\n", "\t\t\tlives = row.lives,\n", 1, "rows", "a stored row keeps"),
    ("R9", H, "\t\t\t\t\trevives = Hiscores.revives(event.revives),\n", "", 1, "rows", "submission"),
    ("R10", H, "\t\t\t\t\trevives = Hiscores.revives(event.revives),\n", "\t\t\t\t\trevives = event.revives,\n", 1, "rows", "submission"),
    ("R11", H, "\t\tlives = spent,\n\t\trevives = Hiscores.revives(attempt.revives),\n", "\t\tlives = spent,\n", 1, "rows", "top-10 list carries"),
    ("R12", H, "\t\t\t\trevives = Hiscores.revives(e.revives), -- f0186: and the revives\n", "", 1, "rows", "top-10 list carries"),
    ("R13", H, "\t\t\tlives = Hiscores.lives(row.lives),\n\t\t\trevives = Hiscores.revives(row.revives),\n", "\t\t\tlives = Hiscores.lives(row.lives),\n", 1, "rows", "top-10 list carries"),
    ("R14", H, "\t\tat = 0,\n\t\tlives = Hiscores.lives(row.lives),\n\t\trevives = Hiscores.revives(row.revives),\n", "\t\tat = 0,\n\t\tlives = Hiscores.lives(row.lives),\n", 1, "rows", "top-10 list carries"),
    ("R15", H, "\t\t\tlives = e.lives,\n\t\t\trevives = e.revives,\n", "\t\t\tlives = e.lives,\n", 1, "rows", "top-10 list carries"),
    ("R16", H, "level = companion.level, revives = Hiscores.revives(companion.revives) }", "level = companion.level }", 1, "rows", "a player's best"),
    ("R17", H, "return attempt.score > stored.score or (attempt.score == stored.score and attempt.level > stored.level)",
     "return attempt.score > stored.score or (attempt.score == stored.score and attempt.level > stored.level) or (attempt.score == stored.score and attempt.level == stored.level and (attempt.revives or 0) < (stored.revives or 0))", 1, "rows", "never make a row replace"),
    ("R18", H, "\t\telseif a.level ~= b.level then\n\t\t\treturn a.level > b.level\n\t\tend\n\t\treturn a.userId < b.userId",
     "\t\telseif a.level ~= b.level then\n\t\t\treturn a.level > b.level\n\t\telseif (a.revives or 0) ~= (b.revives or 0) then\n\t\t\treturn (a.revives or 0) < (b.revives or 0)\n\t\tend\n\t\treturn a.userId < b.userId", 1, "rows", "never make a row replace"),
    ("R19", H, "\telseif a.at ~= b.at then", "\telseif (a.revives or 0) ~= (b.revives or 0) then\n\t\treturn (a.revives or 0) < (b.revives or 0)\n\telseif a.at ~= b.at then", 1, "rows", "top-10 list carries"),
    ("R20", H, "\t\tlives = spent,\n\t\trevives = Hiscores.revives(attempt.revives),\n", "\t\tlives = spent,\n\t\trevives = attempt.revives,\n", 1, "rows", "top-10 list carries"),
    ("R21", H, "\t\t\tlives = Hiscores.lives(row.lives),\n\t\t\trevives = Hiscores.revives(row.revives),\n", "\t\t\tlives = Hiscores.lives(row.lives),\n\t\t\trevives = row.revives,\n", 1, "rows", "top-10 list carries"),
    ("R22", H, "\t\tat = 0,\n\t\tlives = Hiscores.lives(row.lives),\n\t\trevives = Hiscores.revives(row.revives),\n", "\t\tat = 0,\n\t\tlives = Hiscores.lives(row.lives),\n\t\trevives = row.revives,\n", 1, "rows", "top-10 list carries"),
    ("L1", L, "\t\telse 0\n\treturn `{Lobby.REVIVES} {string.format(\"%d\", count)}`", "\t\telse 0\n\tif count == 0 then\n\t\treturn \"\"\n\tend\n\treturn `{Lobby.REVIVES} {string.format(\"%d\", count)}`", 1, "boards", "a revive count reads"),
    ("L2", L, "level = r.level, revives = r.revives }", "level = r.level }", 1, "boards", "every row ends"),
    ("L3", L, "{Lobby.revivesText(r.revives)}`)", "{Lobby.revivesText((r :: any).lives)}`)", 1, "boards", "every row ends"),
    ("L4", L, " {Lobby.revivesText(\n\t\tbest.revives\n\t)}`", "`", 1, "boards", "best line"),
    ("L5", L, "`<s>{Lobby.PRICE.struck}</s> {Lobby.PRICE.price} {Lobby.PRICE.sale}`", "`{Lobby.PRICE.struck} {Lobby.PRICE.price} {Lobby.PRICE.sale}`", 1, "price", "the price of a play: 5"),
    ("L6", L, "Lobby.PRICE = table.freeze({ struck = \"5 R$\", price = \"1 R$\", sale = \"SALE\" })", "Lobby.PRICE = { struck = \"5 R$\", price = \"1 R$\", sale = \"SALE\" }", 1, "price", "the price of a play: 5"),
    ("L7", L, "else `A GAME: {Lobby.salePrice()}`", "else \"1 ROBUX A GAME\"", 1, "price", "wherever it showed"),
    ("L8", L, "line = if mode == \"closed\" then \"STORE UNAVAILABLE\" else `A GAME: {Lobby.salePrice()}`", "line = `A GAME: {Lobby.salePrice()}`", 1, "price", "free, held and closed"),
    ("T1", TP, "local price = if product == \"play\" then Lobby.salePrice() else Flow.OFFER.price", "local price = Flow.OFFER.price", 1, "price", "test purchase screen"),
    ("T2", TP, "local price = if product == \"play\" then Lobby.salePrice() else Flow.OFFER.price", "local price = Lobby.salePrice()", 1, "price", "test purchase screen"),
    ("T3", TP, "\tlabel.RichText = true -- f0186: a play's price is struck through\n", "", 1, "price", "test purchase screen"),
    ("P1", PV, "\tline.RichText = true -- f0186: the price of a play is struck through (Lobby.salePrice)\n", "", 1, "price", "pay line as rich text"),
    ("L9", L, "\t\t\tand n <= 2 ^ 53 - 1\n", "\t\t\tand n ~= math.huge\n", 1, "boards", "a revive count reads"),
    ("F1", F, "\tif play.phase ~= \"gameover\" then\n\t\treturn nil\n\tend\n\treturn Lobby.revivesText", "\treturn Lobby.revivesText", 1, "gameover", "the revives line"),
    ("F2", F, "\treturn Lobby.revivesText(play.revives)", "\treturn if play.revives then Lobby.revivesText(play.revives) else nil", 1, "gameover", "the revives line"),
    ("F3", F, "detail = `SCORE {string.format(\"%d\", play.score)}   LEVEL {play.level}`,", "detail = `SCORE {string.format(\"%d\", play.score)}   LEVEL {play.level}` .. (if play.revives then `   REVIVES {play.revives}` else \"\"),", 2, "gameover", "overlay is unchanged"),
    ("V1", V, "label.Visible = line ~= nil", "label.Visible = true", 1, "gameover", "RevivesView draws"),
    ("V2", V, "UDim2.fromScale(0.2, 0.64)", "UDim2.fromScale(0.2, 0.55)", 1, "gameover", "RevivesView draws"),
    ("V3", V, "\tgui.DisplayOrder = 1 -- above Flow's fade", "\tgui.DisplayOrder = 0 -- above Flow's fade", 1, "gameover", "RevivesView draws"),
    ("M1", M, "\tRevivesView.show(frame.play) -- f0186: the revives the run used, at the game over\n", "", 1, "gameover", "client's Main boots"),
    ("M2", M, "RevivesView.start()\n", "", 1, "gameover", "client's Main boots"),
    ("S4", S, "\t\t\t\tlives = lives,\n\t\t\t\trevives = revives,\n\t\t\t}", "\t\t\t\tlives = lives,\n\t\t\t}", 1, "submit", "HiscoreStore's real source"),
    ("S5", S, "\t\t\t\tlives = lives,\n\t\t\t\trevives = revives,\n\t\t\t}, now, run", "\t\t\t\tlives = lives,\n\t\t\t}, now, run", 1, "submit", "HiscoreStore's real source"),
    ("D1", GD, "**Revives on the boards (f0186)", "**Revives (f0186)", 1, "docs", "game-design.md's paid play"),
    ("D2", GD, "**A free game per game (f0186)", "**A free game (f0186)", 1, "docs", "game-design.md's paid play"),
    ("D3", GD, "the score, the level reached and the revives the run used (f0186)", "the score and the level reached", 1, "docs", "game-design.md's paid play"),
    ("D4", AR, "Flow -> Lobby\n", "", 1, "docs", "architecture.md declares"),
]

tmp = tempfile.mkdtemp(prefix="f0186-mutants-")
def cleanup(*_):
    if tmp.startswith(tempfile.gettempdir()) and "f0186-mutants-" in tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(1)
signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

def sh(cmd, cwd, check=True):
    return subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str), text=True, capture_output=True, check=check)

def replace_nth(s, old, new, n):
    at = -1
    for _ in range(n):
        at = s.find(old, at + 1)
        if at < 0:
            return None
    return s[:at] + new + s[at + len(old):]

def main():
    want = set(sys.argv[1:])
    repo = os.path.join(tmp, "repo")
    sh(["git", "clone", "--quiet", "--shared", "--no-checkout", SRC_REPO, repo], tmp)
    sh(["git", "checkout", "--quiet", BASE], repo)
    sh(["git", "apply", os.path.join(HERE, "prototype.patch")], repo)
    dest = os.path.join(repo, "pickman", "tests", "acceptance", "f0186")
    os.makedirs(dest)
    for name in os.listdir(os.path.join(ISSUE, "acceptance")):
        shutil.copy(os.path.join(ISSUE, "acceptance", name), dest)
    base = sh(f"./zn run --time 300 -- bash -c 'cd pickman && lune run tests/run -- {A}*.spec.luau'", repo, check=False)
    if base.returncode != 0:
        print(base.stdout[-3000:] + base.stderr[-2000:])
        print("BASELINE FAILED: the unmutated prototype must pass every f0186 spec")
        return 1
    print("baseline: every f0186 spec passes on the unmutated prototype")
    results = []
    for mid, path, old, new, nth, spec, case in MUTANTS:
        if want and mid not in want:
            continue
        full = os.path.join(repo, path)
        original = open(full).read()
        mutated = replace_nth(original, old, new, nth)
        if mutated is None:
            results.append((mid, "NOT APPLIED"))
            continue
        open(full, "w").write(mutated)
        try:
            out = sh(f"./zn run --time 120 -- bash -c 'cd pickman && lune run tests/run -- {A}{spec}.spec.luau'", repo, check=False)
            text = out.stdout + out.stderr
            lines = text.splitlines()
            verdict = "SURVIVED"
            for i, line in enumerate(lines):
                if line.startswith("FAIL ") and "::" in line and case in line:
                    msg = lines[i + 1] if i + 1 < len(lines) else ""
                    verdict = "killed" if ("expected" in msg or "section lacks:" in msg) else "ERROR: " + msg.strip()
                    break
            results.append((mid, verdict))
        finally:
            open(full, "w").write(original)
    for mid, verdict in results:
        print(f"{mid}: {verdict}")
    shutil.rmtree(tmp, ignore_errors=True)
    return 0 if all(v == "killed" for _, v in results) else 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
