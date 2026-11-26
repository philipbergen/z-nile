# f0216 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, copies this item's folder in, applies prototype.patch there (the four Logic features),
# runs the intended state, then applies each mutant (and each correct variant) to that clone, runs the row's spec
# files from the clone's invaders/, restores the file, and deletes the clone at the end.
# A mutant is killed when its spec run reports a FAIL whose message is an assertion ("expected ..."), not a
# syntax, type or require error. A correct variant (CV) must stay green.
# Usage, from anywhere: python3 -I <this file> [id prefixes...]
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="f0216-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "invaders")
A = ".tracker/issues/f0216/acceptance/"
FORM = [A + "formation.spec.luau"]
BAR = [A + "barriers.spec.luau"]
SHOT = [A + "shots.spec.luau"]
MYS = [A + "mystery.spec.luau"]
LIV = [A + "lives.spec.luau"]
WAV = [A + "waves.spec.luau"]
GAME = [A + "game.spec.luau"]
ALL = FORM + BAR + SHOT + MYS + LIV + WAV + GAME
L = "src/shared/Logic/"
FO = L + "Formation/init.luau"
BA = L + "Barriers/init.luau"
MY = L + "Mystery/init.luau"
CL = L + "Classic/init.luau"
RN = L + "Classic/Rng.luau"

M = [
    # Formation
    ("F1 ten columns", FO, "\tcols = 11,", "\tcols = 10,", FORM),
    ("F2 points front to back reversed", FO, "points = table.freeze({ 10, 10, 20, 20, 30 })", "points = table.freeze({ 30, 20, 20, 10, 10 })", FORM),
    ("F3 a fixed wait of 55", FO, "return math.max(f.config.minInterval, f.live * f.config.ticksPerAlien)", "return math.max(f.config.minInterval, 55 * f.config.ticksPerAlien)", FORM),
    ("F4 the wait fixed when it starts", FO, "\tf.elapsed += 1\n\tif f.elapsed < Formation.interval(f) then", "\t(f :: any).wait = (f :: any).wait or Formation.interval(f)\n\tf.elapsed += 1\n\tif f.elapsed < (f :: any).wait then", FORM),
    ("F5 the last alien waits two ticks", FO, "\tminInterval = 1,", "\tminInterval = 2,", FORM),
    ("F6 the advance also steps", FO, "\t\tf.d -= c.rowStep\n", "\t\tf.d -= c.rowStep\n\t\tf.x += f.dir * c.stepX\n", FORM),
    ("F7 no reverse", FO, "\t\tf.dir = -f.dir\n", "", FORM),
    ("F8 no margin", FO, "if nl < c.margin or nr > c.fieldWidth - c.margin then", "if nl < 0 or nr > c.fieldWidth then", FORM),
    ("F9 the extent of the whole formation", FO, "\tlocal left = f.x + (minCol - 1) * c.colSpacing\n\tlocal right = f.x + (maxCol - 1) * c.colSpacing + c.width",
     "\tlocal left = f.x\n\tlocal right = f.x + (c.cols - 1) * c.colSpacing + c.width", FORM),
    ("F10 a hit anywhere in the cell", FO, "\tif x >= x0 and x < x1 and d >= d0 and d < d1 then", "\tif x0 + x1 + d0 + d1 ~= 0 then", FORM),
    ("F11 front is the back-most", FO, "\tfor row = 1, f.config.rows do\n\t\tif Formation.isAlive(f, row, col) then\n\t\t\treturn row",
     "\tfor row = f.config.rows, 1, -1 do\n\t\tif Formation.isAlive(f, row, col) then\n\t\t\treturn row", FORM),
    ("F12 a dead alien killed again counts", FO, "\tif not Formation.isAlive(f, row, col) then\n\t\treturn 0\n\tend\n\tf.alive",
     "\tif row < 1 or row > f.config.rows or col < 1 or col > f.config.cols then\n\t\treturn 0\n\tend\n\tf.alive", FORM),
    # Barriers
    ("B1 five rows", BA, "\trows = 6,", "\trows = 5,", BAR),
    ("B2 erosion ignores the travel", BA, "local c, r = col + o[1], row + o[2] * travel", "local c, r = col + o[1], row + o[2]", BAR),
    ("B3 a touching box erases", BA, "if bx < x1 and bx + l.block > x0 and grid[k] then", "if bx <= x1 and bx + l.block > x0 and grid[k] then", BAR),
    ("B4 the shot goes on after a block", CL, "\t\t\tBarriers.erode(g.barriers, bunker, col, row, 1)\n\t\t\tg.shot = nil\n\t\t\ttable.insert(events, { kind = \"BarrierHit\" })\n\t\t\treturn false",
     "\t\t\tBarriers.erode(g.barriers, bunker, col, row, 1)\n\t\t\ttable.insert(events, { kind = \"BarrierHit\" })", BAR),
    ("B5 the shot jumps its speed at once", CL, "\tfor _ = 1, c.shotSpeed do\n\t\tshot.d += 1", "\tfor _ = 1, 1 do\n\t\tshot.d += c.shotSpeed", BAR),
    ("B6 an alien shot erodes like the cannon's", CL, "Barriers.erode(g.barriers, bunker, col, row, -1)", "Barriers.erode(g.barriers, bunker, col, row, 1)", BAR),
    ("B7 marching aliens erase nothing", CL, "\tif moved then\n\t\teraseUnder(g)\n", "\tif moved then\n", BAR),
    ("B8 only an advance erases", CL, "\tif moved then\n\t\teraseUnder(g)\n", "\tif moved then\n\t\tif moved == \"advance\" then\n\t\t\teraseUnder(g)\n\t\tend\n", BAR),
    ("B9 an alien's hit names no slot", CL, "{ kind = \"BarrierHit\", slot = bomb.slot }", "{ kind = \"BarrierHit\" }", BAR),
    # Shots
    ("S1 a fire replaces the flying shot", CL, "if fire and g.shot == nil then", "if fire then", SHOT),
    ("S2 the shot lives past the far end", CL, "if shot.d >= c.fieldDepth then", "if shot.d >= c.fieldDepth + 40 then", SHOT),
    ("S3 the shot goes through the alien", CL, "\t\t\tlocal points = Formation.kill(g.formation, arow, acol)\n\t\t\tg.shot = nil\n",
     "\t\t\tlocal points = Formation.kill(g.formation, arow, acol)\n", SHOT),
    ("S4 any move number accepted", CL, "local m = if move == -1 then -1 elseif move == 1 then 1 else 0", "local m = if type(move) == \"number\" then move else 0", SHOT),
    ("S5 the cannon clamped to the field's edges", CL, "c.cannonHalf, c.fieldWidth - 1 - c.cannonHalf)", "0, c.fieldWidth - 1)", SHOT),
    ("S6 any truthy fire", CL, "return m, input.fire == true", "return m, input.fire ~= nil and input.fire ~= false", SHOT),
    ("S7 always the first free slot", CL, "local s = (g.nextSlot - 1 + i) % 3 + 1", "local s = i + 1", SHOT),
    ("S8 no slot limit", CL, "\t\tif not slotTaken(g, s) then", "\t\tif true then", SHOT),
    ("S9 the reload one tick short", CL, "if f.live == 0 or g.reloadElapsed < Classic.reloadTicks(g.score) then", "if f.live == 0 or g.reloadElapsed < Classic.reloadTicks(g.score) - 1 then", SHOT),
    ("S10 the reload steps after the threshold", CL, "\t\tif score >= r.score then", "\t\tif score > r.score then", SHOT),
    ("S11 aimed from the leftmost column", CL, "\t\t\tif dist < best then", "\t\t\tif best == math.huge then", SHOT),
    ("S12 the shot from the front row's place", CL, "\tlocal row = Formation.front(f, col)\n\tassert(row, \"a living column has a front\")", "\tlocal row = 1", SHOT),
    ("S13 the generator never advances", CL, "\t\tg.rng, pick = Rng.next(g.rng, #columns)", "\t\tlocal _\n\t\t_, pick = Rng.next(g.rng, #columns)", SHOT),
    ("S14 the seed ignored", RN, "\treturn s % (MODULUS - 1) + 1", "\treturn 12345", SHOT),
    ("S15 the cannon's right edge misses", CL, "and bomb.x <= g.cannon + c.cannonHalf", "and bomb.x < g.cannon + c.cannonHalf", SHOT),
    ("S16 the cannon moves after the shots", CL, [
        ("\tg.cannon = math.clamp(g.cannon + move * c.cannonSpeed, c.cannonHalf, c.fieldWidth - 1 - c.cannonHalf)\n", ""),
        ("\tlocal moved = Formation.tick(g.formation)\n", "\tg.cannon = math.clamp(g.cannon + move * c.cannonSpeed, c.cannonHalf, c.fieldWidth - 1 - c.cannonHalf)\n\tlocal moved = Formation.tick(g.formation)\n"),
    ], None, SHOT),
    ("S17 a fire while flying is queued", CL, "\tif fire and g.shot == nil then\n\t\tg.shot = { x = g.cannon, d = c.cannonDepth - 1 }",
     "\tif fire then\n\t\t(g :: any).queued = true\n\tend\n\tif (g :: any).queued and g.shot == nil then\n\t\t(g :: any).queued = nil\n\t\tg.shot = { x = g.cannon, d = c.cannonDepth - 1 }", SHOT),
    ("S18 the cannon's left edge misses", CL, "and bomb.x >= g.cannon - c.cannonHalf", "and bomb.x > g.cannon - c.cannonHalf", SHOT),
    ("S19 the higher column on a tie", CL, "\t\t\tif dist < best then", "\t\t\tif dist <= best then", SHOT),
    # Mystery
    ("M1 one tick early", MY, "\tevery = 1500,", "\tevery = 1499,", MYS),
    ("M2 the first from the right", MY, "return { config = config, x = nil, dir = 1, nextDir = 1, elapsed = 0 }", "return { config = config, x = nil, dir = 1, nextDir = -1, elapsed = 0 }", MYS),
    ("M3 always the same side", MY, "\t\t\tm.nextDir = -m.nextDir\n", "", MYS),
    ("M4 more than 8 aliens", MY, "if m.elapsed >= c.every and live >= c.minAliens then", "if m.elapsed >= c.every and live > c.minAliens then", MYS),
    ("M5 the table one shot off", MY, "return values[shots % #values + 1]", "return values[(shots - 1) % #values + 1]", MYS),
    ("M6 the box one unit wide", MY, "return x >= sx and x < sx + c.width and", "return x >= sx and x <= sx + c.width and", MYS),
    ("M7 the hit's tick counts toward the next", CL, "\tif shipHit then\n\t\treturn events", "\tif false then\n\t\treturn events", MYS),
    ("M8 counted while not playing", CL, "\tif g.phase == \"dying\" or g.phase == \"waveclear\" then\n\t\tg.timer -= 1",
     "\tif g.phase == \"dying\" or g.phase == \"waveclear\" then\n\t\tMystery.tick(g.mystery, g.formation.live)\n\t\tg.timer -= 1", MYS),
    # Lives
    ("L1 four lives", CL, "\tlives = 3,\n\treviveLives = 3,", "\tlives = 4,\n\treviveLives = 3,", LIV),
    ("L2 the shots stay after a hit", CL, "\t\tg.lives -= 1\n\t\tg.shot = nil\n\t\tg.bombs = {}\n", "\t\tg.lives -= 1\n", LIV),
    ("L3 a short dying pause", CL, "\tdyingTicks = 120,", "\tdyingTicks = 119,", LIV),
    ("L4 the cannon stays where it died", CL, "\t\t\tg.phase = \"playing\"\n\t\t\tg.cannon = c.cannonStart\n", "\t\t\tg.phase = \"playing\"\n", LIV),
    ("L5 input moves the cannon while dying", CL, "\tif g.phase == \"dying\" or g.phase == \"waveclear\" then\n\t\tg.timer -= 1",
     "\tif g.phase == \"dying\" or g.phase == \"waveclear\" then\n\t\tlocal mv = sanitize(input)\n\t\tg.cannon += mv\n\t\tg.timer -= 1", LIV),
    ("L6 one life left plays on", CL, "\t\tif g.lives <= 0 then\n\t\t\tendGame(g, \"lives\", events)", "\t\tif g.lives < 0 then\n\t\t\tendGame(g, \"lives\", events)", LIV),
    ("L7 the extra life past 1,500", CL, "if not g.extraLifeGiven and g.score >= g.config.extraLifeScore then", "if not g.extraLifeGiven and g.score > g.config.extraLifeScore then", LIV),
    ("L8 an extra life every time", CL, "if not g.extraLifeGiven and g.score >= g.config.extraLifeScore then", "if g.score >= g.config.extraLifeScore and g.score - points < g.config.extraLifeScore + 1000 then", LIV),
    ("L9 the ship's points never win the extra life", CL, "\t\t\tMystery.remove(g.mystery)\n\t\t\tg.shot = nil\n\t\t\ttable.insert(events, { kind = \"MysteryHit\", points = points })\n\t\t\taddScore(g, points, events)",
     "\t\t\tMystery.remove(g.mystery)\n\t\t\tg.shot = nil\n\t\t\ttable.insert(events, { kind = \"MysteryHit\", points = points })\n\t\t\tg.score += points", LIV),
    ("L10 a hit does not end the tick", CL, "\t\t\tg.timer = c.dyingTicks\n\t\tend\n\t\treturn events\n\tend\n", "\t\t\tg.timer = c.dyingTicks\n\t\tend\n\tend\n", LIV),
    ("L11 the formation moves before the alien shots", CL, [
        ("\tlocal moved = Formation.tick(g.formation)\n\tif moved then\n\t\teraseUnder(g)\n\t\ttable.insert(events, {", "\tif false then\n\t\ttable.insert(events, {"),
        ("\tif moveBombs(g, events) then", "\tlocal moved = Formation.tick(g.formation)\n\tif moved then\n\t\teraseUnder(g)\n\t\tif moved == \"advance\" then\n\t\t\tlocal _, _, near = Formation.extent(g.formation)\n\t\t\tif near and near <= c.invasionDepth then\n\t\t\t\tendGame(g, \"invasion\", events)\n\t\t\t\treturn events\n\t\t\tend\n\t\tend\n\tend\n\tif moveBombs(g, events) then"),
    ], None, LIV),
    ("L12 the respawn names no lives", CL, "{ kind = \"Respawn\", lives = g.lives }", "{ kind = \"Respawn\" }", LIV),
    # Waves, invasion and the revive
    ("W1 invasion costs a life", CL, "\t\t\tif near and near <= c.invasionDepth then\n\t\t\t\tendGame(g, \"invasion\", events)\n\t\t\t\treturn events",
     "\t\t\tif near and near <= c.invasionDepth then\n\t\t\t\tg.lives -= 1\n\t\t\t\tif g.lives <= 0 then\n\t\t\t\t\tendGame(g, \"invasion\", events)\n\t\t\t\t\treturn events\n\t\t\t\tend", WAV),
    ("W2 invasion below the line only", CL, "if near and near <= c.invasionDepth then", "if near and near < c.invasionDepth then", WAV),
    ("W3 invasion judged on row 1", CL, "\t\t\tlocal _, _, near = Formation.extent(g.formation)\n", "\t\t\tlocal near = g.formation.d\n", WAV),
    ("W4 a revive while playing", CL, "\tif g.phase ~= \"gameover\" then\n\t\treturn false\n\tend\n\tg.lives = g.config.reviveLives", "\tg.lives = g.config.reviveLives", WAV),
    ("W5 a revive keeps the formation", CL, "\tg.reason = nil\n\tstartWave(g)\n\treturn true", "\tg.reason = nil\n\tg.phase = \"playing\"\n\treturn true", WAV),
    ("W6 a revive resets the score", CL, "\tg.revives += 1\n", "\tg.revives += 1\n\tg.score = 0\n", WAV),
    ("W7 a revive not counted", CL, "\tg.revives += 1\n", "", WAV),
    ("W8 the next wave at the same depth", CL, "return c.firstDepth - c.formation.rowStep * ((wave - 1) % c.waveCycle)", "return c.firstDepth", WAV),
    ("W9 cycling after 9", CL, "\twaveCycle = 8,", "\twaveCycle = 9,", WAV),
    ("W10 the barriers kept across waves", CL, "\tg.barriers = Barriers.new(c.barriers)\n\tg.mystery = Mystery.new(c.mystery)\n\tg.shot = nil", "\tg.mystery = Mystery.new(c.mystery)\n\tg.shot = nil", WAV),
    ("W11 a short wave pause", CL, "\twaveClearTicks = 120,", "\twaveClearTicks = 119,", WAV),
    ("W12 the bombs stay at a clear", CL, "\t\tg.timer = c.waveClearTicks\n\t\tg.shot = nil\n\t\tg.bombs = {}\n", "\t\tg.timer = c.waveClearTicks\n\t\tg.shot = nil\n", WAV),
    ("W13 the clear decided after the alien shots", CL, [
        ("\tif cleared then\n", "\tif false then\n"),
        ("\tlocal moved = Formation.tick(g.formation)\n", "\tif cleared then\n\t\tg.phase = \"waveclear\"\n\t\tg.timer = c.waveClearTicks\n\t\tg.shot = nil\n\t\tg.bombs = {}\n\t\tMystery.remove(g.mystery)\n\t\ttable.insert(events, { kind = \"WaveClear\", wave = g.wave })\n\t\treturn events\n\tend\n\tlocal moved = Formation.tick(g.formation)\n"),
    ], None, WAV),
    ("W14 the wave start keeps the cannon", CL, "\tg.nextSlot = 1\n\tg.cannon = c.cannonStart\n", "\tg.nextSlot = 1\n", WAV),
    ("W15 the wave start keeps the reload", CL, "\tg.reloadElapsed = 0\n\tg.nextSlot = 1\n", "\tg.nextSlot = 1\n", WAV),
    ("W16 the wave start keeps the ship", CL, "\tg.mystery = Mystery.new(c.mystery)\n\tg.shot = nil", "\tg.shot = nil", WAV),
    ("W17 the wave start keeps the slot turn", CL, "\tg.nextSlot = 1\n\tg.cannon", "\tg.cannon", WAV),
    ("W18 the wave start keeps the ship's side", CL, "\tg.mystery = Mystery.new(c.mystery)\n\tg.shot = nil", "\tlocal nd = g.mystery.nextDir\n\tg.mystery = Mystery.new(c.mystery)\n\tg.mystery.nextDir = nd\n\tg.shot = nil", WAV),
    # The game as a whole
    ("G1 sparse bombs by slot", CL, "\ttable.insert(g.bombs, { x = (x0 + x1) // 2, d = d0, slot = slot })", "\tg.bombs[slot * 2] = { x = (x0 + x1) // 2, d = d0, slot = slot }", GAME),
    ("G2 the seed not floored", RN, "local s = if type(seed) == \"number\" then math.floor(seed) else 0", "local s = if type(seed) == \"number\" then seed * 1000 else 0", GAME),
    ("G3 a NaN seed kept", RN, "\tif s ~= s or math.abs(s) == math.huge then\n\t\ts = 0\n\tend\n", "\tif s ~= s then\n\t\ts = 7\n\tend\n", GAME),
    ("G4 tick rate 30", CL, "Classic.TICK_RATE = 60", "Classic.TICK_RATE = 30", GAME),
    ("G5 the march events carry no wait", CL, "\t\t\tinterval = Formation.interval(g.formation),\n", "", GAME),
]

# Correct variants: right changes of the kind f0217 (two players) and f0218 (the view) are expected to make. Each
# must keep every acceptance spec green.
CV = [
    ("CV1 a hit says where", CL, "table.insert(events, { kind = \"AlienHit\", row = arow, col = acol, points = points })", "table.insert(events, { kind = \"AlienHit\", row = arow, col = acol, points = points, x = shot.x, d = shot.d } :: any)", ALL),
    ("CV6 the state learns its player count", CL, "\t\trevives = 0,\n", "\t\trevives = 0,\n\t\tplayers = 1,\n", ALL),
    ("CV2 the formation learns its heading", FO, "\t\tdir = 1,\n\t\telapsed = 0,", "\t\tdir = 1,\n\t\ttoward = -1,\n\t\telapsed = 0,", ALL),
    ("CV3 the layout learns per-bunker depths", BA, "\tblock = 3,\n} :: Layout)", "\tblock = 3,\n\tnears = nil,\n} :: any)", ALL),
    ("CV4 new takes an optional config", CL, "function Classic.new(seed: number): Game\n\tlocal c = Classic.CONFIG", "function Classic.new(seed: number, config: Config?): Game\n\tlocal c = config or Classic.CONFIG", ALL),
    ("CV5 a beat event beside the march", CL, "\t\teraseUnder(g)\n", "\t\teraseUnder(g)\n\t\ttable.insert(events, { kind = \"Beat\" })\n", ALL),
]


def run(specs):
    return subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=600).stdout


def verdict(out, correct):
    lines = out.strip().splitlines()
    sums = [l for l in lines if " passed, " in l and " failed, " in l and "spec files" in l]
    last = sums[-1] if sums else (lines[-1] if lines else "NO OUTPUT")
    failed = "0 failed" not in last
    if correct:
        return ("ok (green)" if not failed else "RED: " + last), not failed
    if not failed:
        return "SURVIVED", False
    msgs = [l for l in lines if l.startswith("     ")]
    if any("expected" in m for m in msgs) and not any(("attempt to" in m or "Unknown require" in m or "syntax" in m.lower()) for m in msgs):
        return "killed", True
    return "ERROR (not an assertion): " + (msgs[0].strip() if msgs else last), False


def main():
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    item = os.path.join(HOME, ".tracker", "issues", "f0216")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    subprocess.run(["git", "-C", CLONE, "apply", os.path.join(HERE, "prototype.patch")], check=True)
    only = sys.argv[1:]
    out = run(ALL)
    print("intended".ljust(48), verdict(out, True)[0], flush=True)
    bad = 0
    for mid, rel, old, new, specs in M + CV:
        if only and not any(mid.startswith(o) for o in only):
            continue
        f = os.path.realpath(os.path.join(HOME, rel))
        if not f.startswith(TMP + os.sep):
            sys.exit(f"refusing to write outside the clone: {f}")
        src = open(f).read()
        pairs = old if isinstance(old, list) else [(old, new)]
        edited, anchors = src, True
        for o, n in pairs:
            if edited.count(o) != 1:
                print(mid.ljust(48), "ANCHOR", edited.count(o), repr(o[:40]), flush=True)
                anchors = False
                break
            edited = edited.replace(o, n)
        if not anchors:
            bad += 1
            continue
        open(f, "w").write(edited)
        try:
            msg, good = verdict(run(specs), mid.startswith("CV"))
        finally:
            open(f, "w").write(src)
        if not good:
            bad += 1
        print(mid.ljust(48), msg, flush=True)
    print(f"{len(M)} mutants, {len(CV)} correct variants, {bad} not as intended")
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        code = main()
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    sys.exit(code)
