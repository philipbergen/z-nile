# f0217 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, reads f0216's prototype and acceptance specs from this repository (read only), refuses
# unless they are the ones this check was cut from (their SHA-256 below), applies f0216's prototype and then this
# item's prototype.patch in the clone, runs f0216's specs and this item's specs on the unmutated base (all must
# pass), then applies each mutant (and each correct variant) in turn, runs the row's spec files from the clone's
# invaders/, restores the file, and deletes the clone at the end.
# A mutant is killed when its spec run reports a FAIL whose message is an assertion ("expected ..."), not a syntax,
# type or require error. A correct variant (CV) must keep every spec green, f0216's included.
# Usage, from anywhere: ./zn run --time 1500 -- python3 -I <this file> [id prefixes...]
import hashlib, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="f0217-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "invaders")

# f0216's prototype and specs this base was cut from (its prep branch, a19b4281, 2026-11-15)
F0216_PATCH_SHA = "1785153a319171a79f87b5ccc0a70c5f2dbdf2f72d3584ee5f9d47d9634979ff"
F0216_SPECS_SHA = "2c8b62b76d3bd365998ea6f8b0a136ea11ecf30f5fd55a525343345fe6b9880b"
F0216_SPECS = ["barriers", "formation", "game", "lives", "mystery", "shots", "waves"]
F0216_REFS = ["HEAD", "origin/main", "origin/prep-invaders-classic-rules", "prep-invaders-classic-rules"]

A = ".tracker/issues/f0217/acceptance/"
FIELD = [A + "field.spec.luau"]
FLY = [A + "flyin.spec.luau"]
CROSS = [A + "crossing.spec.luau"]
SIDES = [A + "sides.spec.luau"]
SURV = [A + "survivor.spec.luau"]
MATCH = [A + "match.spec.luau"]
MINE = FIELD + FLY + CROSS + SIDES + SURV + MATCH
B = ".tracker/issues/f0216/acceptance/"
THEIRS = [B + n + ".spec.luau" for n in F0216_SPECS]
ALL = MINE + THEIRS
L = "src/shared/Logic/"
TP = L + "TwoPlayer/init.luau"
CL = L + "Classic/init.luau"

M = [
    # The field (AC1)
    ("F1 the field one and a half deep", TP, "local DEPTH = 2 * CLASSIC.fieldDepth", "local DEPTH = 3 * CLASSIC.fieldDepth // 2", FIELD),
    ("F2 the half turn off by one", TP, "return g.config.pair.fieldWidth - 1 - x, g.config.fieldDepth - 1 - d", "return g.config.pair.fieldWidth - x, g.config.fieldDepth - d", FIELD),
    ("F3 a box turned as points", TP, "return w - x1, depth - d1, w - x0, depth - d0", "return w - 1 - x1, depth - 1 - d1, w - 1 - x0, depth - 1 - d0", FIELD),
    ("F5 groups of 9 columns", TP, "TwoPlayer.PAIR = frozenCopy(Formation.CLASSIC, { cols = 8 })", "TwoPlayer.PAIR = frozenCopy(Formation.CLASSIC, { cols = 9 })", FIELD),
    ("F6 a solo number changed", TP, "pair = frozenCopy(CLASSIC, { fieldDepth = DEPTH, formation = TwoPlayer.PAIR }),", "pair = frozenCopy(CLASSIC, { fieldDepth = DEPTH, formation = TwoPlayer.PAIR, cannonSpeed = 2 }),", FIELD),
    ("F7 player 2's moves in the field's frame", TP, "\t\t\t\tlocal move, fire = Classic.sanitize(inputOf(inputs, p))\n", "\t\t\t\tlocal move, fire = Classic.sanitize(inputOf(inputs, p))\n\t\t\t\tif p == 2 then\n\t\t\t\t\tmove = -move\n\t\t\t\tend\n", FIELD),
    ("F8 the lone run keeps the solo depth", TP, "lone = frozenCopy(CLASSIC, { fieldDepth = DEPTH, formation = Formation.CLASSIC }),", "lone = frozenCopy(CLASSIC, { formation = Formation.CLASSIC }),", FIELD),
    # The fly-in (AC2)
    ("Y1 a flyer every 3 ticks", TP, "flyIn = table.freeze({ speed = 6, gap = 2, loneGap = 3, lane = MID - 4 }),", "flyIn = table.freeze({ speed = 6, gap = 3, loneGap = 3, lane = MID - 4 }),", FLY),
    ("Y2 one group, then the other", TP, "\tfor i = 1, n do\n\t\tfor _, l in lists do\n\t\t\tlocal place = l.places[i]", "\tfor _, l in lists do\n\t\tfor i = 1, n do\n\t\t\tlocal place = l.places[i]", FLY),
    ("Y3 back row first", TP, "\t\tfor row = 1, fc.rows do\n\t\t\ttable.insert(out, { row, col })", "\t\tfor row = fc.rows, 1, -1 do\n\t\t\ttable.insert(out, { row, col })", FLY),
    ("Y4 player 2's columns in their own order", TP, "local col = if p == 1 then i else fc.cols + 1 - i", "local col = i", FLY),
    ("Y5 the flyers start on the field", TP, "\t\tx0, d0 = w - s, fly.lane\n", "\t\tx0, d0 = w - 12 - s, fly.lane\n", FLY),
    ("Y6 the turn first, then west", TP, "\tlocal across = w - tx0\n\tlocal down = math.abs(td0 - fly.lane)\n\tlocal s = math.clamp(fly.speed * (g.flyTick - fl.start), 0, across + down)\n\tlocal x0, d0\n\tif s <= across then\n\t\tx0, d0 = w - s, fly.lane\n\telse\n\t\tx0 = tx0\n\t\td0 = fly.lane + (if td0 < fly.lane then -1 else 1) * (s - across)\n\tend",
     "\tlocal across = w - tx0\n\tlocal down = math.abs(td0 - fly.lane)\n\tlocal s = math.clamp(fly.speed * (g.flyTick - fl.start), 0, across + down)\n\tlocal x0, d0\n\tif s <= down then\n\t\tx0, d0 = w, fly.lane + (if td0 < fly.lane then -1 else 1) * s\n\telse\n\t\tx0, d0 = w - (s - down), td0\n\tend", FLY),
    ("Y7 a slower stream", TP, "flyIn = table.freeze({ speed = 6, gap = 2, loneGap = 3, lane = MID - 4 }),", "flyIn = table.freeze({ speed = 3, gap = 2, loneGap = 3, lane = MID - 4 }),", FLY),
    ("Y8 the lane off the midline", TP, "flyIn = table.freeze({ speed = 6, gap = 2, loneGap = 3, lane = MID - 4 }),", "flyIn = table.freeze({ speed = 6, gap = 2, loneGap = 3, lane = MID - 20 }),", FLY),
    ("Y9 flyers can't be shot", TP, "\t\tfor i, fl in g.flyers do\n\t\t\tlocal x0, d0, x1, d1 = TwoPlayer.flyerBox(g, fl)\n\t\t\tif fx >= x0", "\t\tfor i, fl in {} :: { Flyer } do\n\t\t\tlocal x0, d0, x1, d1 = TwoPlayer.flyerBox(g, fl)\n\t\t\tif fx >= x0", FLY),
    ("Y10 a flyer's points to its group's player", TP, "\t\t\t\tkill(g, fl.player, fl.row, fl.col, p, events)", "\t\t\t\tkill(g, fl.player, fl.row, fl.col, fl.player, events)", FLY),
    ("Y11 a waiting place can be hit", TP, "if row and col and not g.sides[q].waiting[slotIndex(f, row, col)] then", "if row and col then", FLY),
    ("Y12 the march during the fly-in", TP, "\tif flying then\n\t\t-- 6. the fly-in ends once every alien is in its place or shot\n\t\tif #g.flyers == 0 then\n\t\t\tg.phase = \"playing\"\n\t\t\ttable.insert(events, { kind = \"Formed\", wave = g.wave })\n\t\tend\n\t\treturn events\n\tend",
     "\tif flying then\n\t\t-- 6. the fly-in ends once every alien is in its place or shot\n\t\tif #g.flyers == 0 then\n\t\t\tg.phase = \"playing\"\n\t\t\ttable.insert(events, { kind = \"Formed\", wave = g.wave })\n\t\tend\n\tend", FLY),
    ("Y13 the cannons wait for the formation", TP, "\t\t\telseif run.phase == \"playing\" then\n\t\t\t\tacting[p] = true\n", "\t\t\telseif run.phase == \"playing\" and not flying then\n\t\t\t\tacting[p] = true\n", FLY),
    ("Y14 no Formed event", TP, "\t\t\ttable.insert(events, { kind = \"Formed\", wave = g.wave })\n", "", FLY),
    ("Y15 a flyer shot is not killed", TP, "\t\t\t\ttable.remove(g.flyers, i)\n\t\t\t\trun.shot = nil\n\t\t\t\tkill(g, fl.player, fl.row, fl.col, p, events)", "\t\t\t\ttable.remove(g.flyers, i)\n\t\t\t\trun.shot = nil\n\t\t\t\ttable.insert(events, { kind = \"AlienHit\", player = fl.player, shooter = p, row = fl.row, col = fl.col, points = 10 })\n\t\t\t\tClassic.addScore(run, 10, {})", FLY),
    ("Y16 a shot flyer still flies", TP, "\t\t\t\ttable.remove(g.flyers, i)\n\t\t\t\trun.shot = nil\n", "\t\t\t\trun.shot = nil\n", FLY),
    ("Y17 the lone stream as tight as a pair's", TP, "local gap = if #lists == 1 then g.config.flyIn.loneGap else g.config.flyIn.gap", "local gap = g.config.flyIn.gap", SURV),
    ("Y19 a flyer lands short of its place", TP, "return x0, d0, x0 + (tx1 - tx0), d0 + (td1 - td0), s == across + down", "return x0, d0, x0 + (tx1 - tx0), d0 + (td1 - td0), s >= across + down - fly.speed + 1", FLY),
    ("Y20 flyers tested in the shooter's frame", TP, "\t\t\tif fx >= x0 and fx < x1 and fd >= d0 and fd < d1 then", "\t\t\tif shot.x >= x0 and shot.x < x1 and shot.d >= d0 and shot.d < d1 then", FLY),
    ("Y21 the other group's waiting places can be hit", TP, "if row and col and not g.sides[q].waiting[slotIndex(f, row, col)] then", "if row and col and (q ~= p or not g.sides[q].waiting[slotIndex(f, row, col)]) then", FLY),
    ("Y22 player 2's waiting places can be hit by player 2", TP, "if row and col and not g.sides[q].waiting[slotIndex(f, row, col)] then", "if row and col and (p == 2 or not g.sides[q].waiting[slotIndex(f, row, col)]) then", FLY),
    ("Y23 Formed names no wave", TP, "table.insert(events, { kind = \"Formed\", wave = g.wave })", "table.insert(events, { kind = \"Formed\" })", FLY),
    # A shot crosses the field (AC3)
    ("X1 the shot ends at the solo far end", TP, "\t\tif shot.d >= g.config.fieldDepth then\n\t\t\trun.shot = nil", "\t\tif shot.d >= CLASSIC.fieldDepth then\n\t\t\trun.shot = nil", CROSS),
    ("X2 the shot goes on to the field's end", TP, "\t\t\tif not g.config.shotsHitPlayers then\n\t\t\t\trun.shot = nil\n\t\t\t\treturn false\n\t\t\tend\n", "", CROSS),
    ("X3 shots hit players by default", TP, "\tshotsHitPlayers = false,", "\tshotsHitPlayers = true,", CROSS),
    ("X4 the other group in the shooter's frame", TP, "for _, target in { { p, shot.x, shot.d }, { o, ox, od } } do", "for _, target in { { p, shot.x, shot.d }, { o, shot.x, shot.d } } do", CROSS),
    ("X5 a kill scores the group's player", TP, "\t\t\t\tkill(g, q, row, col, p, events)", "\t\t\t\tkill(g, q, row, col, q, events)", CROSS),
    ("X6 the far side eroded like the near", TP, "Barriers.erode(other.run.barriers, bunker, bcol, brow, -1)", "Barriers.erode(other.run.barriers, bunker, bcol, brow, 1)", CROSS),
    ("X7 the other's bunkers let shots through", TP, "\t\tbunker, bcol, brow = Barriers.blockAt(other.run.barriers, ox, od)\n", "\t\tbunker, bcol, brow = nil, nil, nil\n", CROSS),
    ("X8 the own bunkers eroded from the far side", TP, "Barriers.erode(run.barriers, bunker, bcol, brow, 1)", "Barriers.erode(run.barriers, bunker, bcol, brow, -1)", CROSS),
    ("X9 the ship tested in the shooter's frame", TP, "\t\tif Mystery.hitAt(g.mystery, fx, fd) then", "\t\tif Mystery.hitAt(g.mystery, shot.x, shot.d) then", CROSS),
    ("X10 the ship's value by the other's count", TP, "local points = Mystery.value(g.mystery, run.shotsFired)", "local points = Mystery.value(g.mystery, other.run.shotsFired)", CROSS),
    ("X11 the ship's lane off the midline", TP, "mystery = frozenCopy(Mystery.CLASSIC, { lane = MID - 4, depth = 8 }),", "mystery = frozenCopy(Mystery.CLASSIC, { lane = MID - 4, depth = 7 }),", CROSS),
    ("X12 player 2's shot first", TP, "\tfor p = 1, 2 do\n\t\tif acting[p] and moveShot(g, p, acting, events) then", "\tfor p = 2, 1, -1 do\n\t\tif acting[p] and moveShot(g, p, acting, events) then", CROSS),
    ("X13 a hit one unit wider", TP, "if acting[o] and math.abs(ox - other.run.cannon) <= c.cannonHalf then", "if acting[o] and math.abs(ox - other.run.cannon) <= c.cannonHalf + 1 then", CROSS),
    ("X14 a hit on a player costs nothing", TP, "\t\t\t\tlocal evs = {}\n\t\t\t\tClassic.hit(other.run, evs)\n\t\t\t\ttag(evs, o, events, p)\n", "", CROSS),
    ("X15 a miss stops at the line", TP, "\t\t\t\ttag(evs, o, events, p)\n\t\t\t\treturn false\n\t\t\tend\n", "\t\t\t\ttag(evs, o, events, p)\n\t\t\t\treturn false\n\t\t\tend\n\t\t\trun.shot = nil\n\t\t\treturn false\n", CROSS),
    ("X16 the hit names no shooter", TP, "\t\t\t\ttag(evs, o, events, p)\n", "\t\t\t\ttag(evs, o, events)\n", CROSS),
    ("X17 the other's bunkers in the shooter's frame", TP, "\t\tbunker, bcol, brow = Barriers.blockAt(other.run.barriers, ox, od)\n", "\t\tbunker, bcol, brow = Barriers.blockAt(other.run.barriers, shot.x, shot.d)\n", CROSS),
    ("X18 a player hit while not playing", TP, "if acting[o] and math.abs(ox - other.run.cannon) <= c.cannonHalf then", "if not other.out and math.abs(ox - other.run.cannon) <= c.cannonHalf then", CROSS),
    ("X19 the ship counts player 1's group only", TP, "local change = Mystery.tick(g.mystery, left)", "local change = Mystery.tick(g.mystery, g.sides[1].run.formation.live)", CROSS),
    ("X20 the ship's hit tick counts", TP, "\t-- 8. the ship\n\tif not shipHit then", "\t-- 8. the ship\n\tif true then", CROSS),
    ("Y18 the ship during the fly-in", TP, "\t\tif #g.flyers == 0 then\n\t\t\tg.phase = \"playing\"", "\t\tif Mystery.tick(g.mystery, left) == \"appear\" then\n\t\t\ttable.insert(events, { kind = \"MysteryAppear\" })\n\t\tend\n\t\tif #g.flyers == 0 then\n\t\t\tg.phase = \"playing\"", FLY),
    ("X21 a player hit by a shot plays on that tick", TP, "\t\t\t\trun.shot = nil\n\t\t\t\tacting[o] = false\n", "\t\t\t\trun.shot = nil\n", CROSS),
    # Each player's own run (AC4)
    ("S1 only player 1's group marches", TP, "\t\tif acting[p] then\n\t\t\tlocal evs = {}\n\t\t\tif Classic.march(side.run, evs) then", "\t\tif acting[p] and p == 1 then\n\t\t\tlocal evs = {}\n\t\t\tif Classic.march(side.run, evs) then", SIDES),
    ("S2 only player 1's group fires", TP, "\t\t\telse\n\t\t\t\tClassic.alienFire(side.run, evs)\n", "\t\t\telseif p == 1 then\n\t\t\t\tClassic.alienFire(side.run, evs)\n", SIDES),
    ("S3 a hit costs both players a life", TP, "\t\t\tif Classic.moveBombs(side.run, evs) then\n\t\t\t\tClassic.hit(side.run, evs)\n", "\t\t\tif Classic.moveBombs(side.run, evs) then\n\t\t\t\tClassic.hit(side.run, evs)\n\t\t\t\tif g.sides[3 - p].run.phase == \"playing\" then\n\t\t\t\t\tClassic.hit(g.sides[3 - p].run, {})\n\t\t\t\tend\n", SIDES),
    ("S4 the extra life names no player", TP, "\tClassic.addScore(g.sides[shooter].run, points, evs)\n\ttag(evs, shooter, events)", "\tClassic.addScore(g.sides[shooter].run, points, evs)\n\tfor _, e in evs do\n\t\ttable.insert(events, e :: any)\n\tend", SIDES),
    ("S5 a hit pauses the whole field", TP, "\t\t\t\tClassic.hit(side.run, evs)\n\t\t\t\tacting[p] = false\n", "\t\t\t\tClassic.hit(side.run, evs)\n\t\t\t\tacting = { false, false }\n", SIDES),
    ("S6 a dying player's group marches", TP, "\t\t\tif run.phase == \"dying\" then\n\t\t\t\ttag(Classic.step(run, nil), p, events)\n", "\t\t\tif run.phase == \"dying\" then\n\t\t\t\ttag(Classic.step(run, nil), p, events)\n\t\t\t\tif run.phase == \"dying\" and not flying then\n\t\t\t\t\tlocal evs = {}\n\t\t\t\t\tClassic.march(run, evs)\n\t\t\t\t\ttag(evs, p, events)\n\t\t\t\tend\n", SIDES),
    ("S7 the respawn names no player", TP, "\t\t\t\ttag(Classic.step(run, nil), p, events)\n", "\t\t\t\tfor _, e in Classic.step(run, nil) do\n\t\t\t\t\ttable.insert(events, e :: any)\n\t\t\t\tend\n", SIDES),
    ("S8 one game over ends the match", TP, "\tlocal flying = g.phase == \"flyin\"\n", "\tfor _, side in g.sides do\n\t\tif side.run.phase == \"gameover\" then\n\t\t\tg.phase = \"over\"\n\t\t\treturn events\n\t\tend\n\tend\n\tlocal flying = g.phase == \"flyin\"\n", SIDES),
    ("S9 a game-over player's group marches on", TP, "\t-- 7. each group marches toward its own player, and fires at them\n\tfor p, side in g.sides do\n\t\tif acting[p] then", "\t-- 7. each group marches toward its own player, and fires at them\n\tfor p, side in g.sides do\n\t\tif acting[p] or (not side.out and side.run.phase == \"gameover\") then", SIDES),
    ("S10 a game-over player's group can't be hit", TP, "if row and col and not g.sides[q].waiting[slotIndex(f, row, col)] then", "if row and col and not g.sides[q].waiting[slotIndex(f, row, col)] and g.sides[q].run.phase ~= \"gameover\" then", SIDES),
    ("S11 the wave ends with either group", TP, "\tlocal left = 0\n\tlocal waitingRevive = false\n\tfor _, side in g.sides do\n\t\tleft += side.run.formation.live\n", "\tlocal left = 0\n\tlocal waitingRevive = false\n\tlocal emptied = false\n\tfor _, side in g.sides do\n\t\tleft += side.run.formation.live\n\t\temptied = emptied or (not side.out and side.run.formation.live == 0)\n", SIDES, [("\tif left == 0 and not waitingRevive then\n", "\tif (left == 0 or emptied) and not waitingRevive then\n")]),
    ("S12 no GroupClear", TP, "\t\ttable.insert(events, { kind = \"GroupClear\", player = q })\n", "", SIDES),
    ("S13 the bombs stay at a clear", TP, "\t\t\tside.run.shot = nil\n\t\t\tside.run.bombs = {}\n\t\tend\n\t\tg.flyers = {}", "\t\t\tside.run.shot = nil\n\t\tend\n\t\tg.flyers = {}", SIDES),
    ("S14 a short wave pause", TP, "\t\tg.timer = CLASSIC.waveClearTicks\n", "\t\tg.timer = CLASSIC.waveClearTicks - 1\n", SIDES),
    ("S15 the runs keep the first wave's depth", TP, "\t\t\trun.wave = g.wave\n", "", SIDES),
    ("S16 the wave ends while a player waits on a revive", TP, "\tif left == 0 and not waitingRevive then\n", "\tif left == 0 then\n", SIDES),
    ("S17 the revived group flies in again", TP, "\tside.waiting = table.create(fc.rows * fc.cols, false)\n\tlocal kept = {}\n\tfor _, fl in g.flyers do\n\t\tif fl.player ~= p then\n\t\t\ttable.insert(kept, fl)\n\t\tend\n\tend\n\tg.flyers = kept\n\treturn true",
     "\tside.waiting = table.create(fc.rows * fc.cols, true)\n\treturn true", SIDES),
    ("S18 a revive restarts both players' wave", TP, "\tClassic.revive(side.run)\n", "\tClassic.revive(side.run)\n\tClassic.startWave(g.sides[3 - p].run)\n", SIDES),
    ("S19 a revive while playing", TP, "\tif side == nil or side.out or side.run.phase ~= \"gameover\" then\n\t\treturn false\n\tend\n\tClassic.revive(side.run)", "\tif side == nil or side.out then\n\t\treturn false\n\tend\n\tClassic.revive(side.run)", SIDES),
    ("S20 the hit player's tick goes on", TP, "\t\t\t\tClassic.hit(side.run, evs)\n\t\t\t\tacting[p] = false\n", "\t\t\t\tClassic.hit(side.run, evs)\n", SIDES),
    ("S21 the revive keeps its flyers", TP, "\tside.waiting = table.create(fc.rows * fc.cols, false)\n\tlocal kept = {}\n\tfor _, fl in g.flyers do\n\t\tif fl.player ~= p then\n\t\t\ttable.insert(kept, fl)\n\t\tend\n\tend\n\tg.flyers = kept\n\treturn true", "\tside.waiting = table.create(fc.rows * fc.cols, false)\n\treturn true", SIDES),
    ("S22 the next wave keeps the ship's side", TP, "\tg.mystery = Mystery.new(g.config.mystery)\n\tg.phase = \"flyin\"", "\tlocal nd = g.mystery.nextDir\n\tg.mystery = Mystery.new(g.config.mystery)\n\tg.mystery.nextDir = nd\n\tg.phase = \"flyin\"", SIDES),
    ("S23 no Respawn at the wave's start", TP, "\t\t\tif dying[p] then\n\t\t\t\ttable.insert(events, { kind = \"Respawn\", player = p, lives = side.run.lives })\n", "\t\t\tif false then\n\t\t\t\ttable.insert(events, { kind = \"Respawn\", player = p, lives = side.run.lives })\n", SIDES),
    ("S24 a revive sized by who is left", TP, "\tClassic.revive(side.run)\n", "\tside.run.config = if liveSides(g) == 1 then g.config.lone else g.config.pair\n\tClassic.revive(side.run)\n", SIDES),
    # A lone survivor (AC5)
    ("V1 the leaving group stays", TP, "\tfor row = 1, f.config.rows do\n\t\tfor col = 1, f.config.cols do\n\t\t\tFormation.kill(f, row, col)\n\t\tend\n\tend\n\tside.waiting", "\tside.waiting", SURV),
    ("V2 an out player revived", TP, "\tif side == nil or side.out or side.run.phase ~= \"gameover\" then\n\t\treturn false\n\tend\n\tClassic.revive(side.run)", "\tif side == nil or side.run.phase ~= \"gameover\" then\n\t\treturn false\n\tend\n\tside.out = false\n\tClassic.revive(side.run)", SURV),
    ("V3 an out player still moves", TP, "\t\tlocal run = side.run\n\t\tif not side.out then\n\t\t\tif run.phase == \"dying\" then", "\t\tlocal run = side.run\n\t\tif side.out then\n\t\t\tlocal move = Classic.sanitize(inputOf(inputs, p))\n\t\t\tClassic.moveCannon(run, move)\n\t\telse\n\t\t\tif run.phase == \"dying\" then", SURV),
    ("V4 the leaving player's flyers stay", TP, "\tside.waiting = table.create(f.config.rows * f.config.cols, false)\n\trun.shot = nil\n\trun.bombs = {}\n\tlocal kept = {}\n\tfor _, fl in g.flyers do\n\t\tif fl.player ~= p then\n\t\t\ttable.insert(kept, fl)\n\t\tend\n\tend\n\tg.flyers = kept\n",
     "\tside.waiting = table.create(f.config.rows * f.config.cols, false)\n\trun.shot = nil\n\trun.bombs = {}\n", SURV),
    ("V5 the survivor keeps the pair's group", TP, "\t\t\trun.config = if lone then g.config.lone else g.config.pair\n", "\t\t\trun.config = g.config.pair\n", SURV),
    ("V6 the out player still waits on a revive", TP, "\t\tif not side.out and side.run.phase == \"gameover\" then\n\t\t\twaitingRevive = true", "\t\tif side.run.phase == \"gameover\" then\n\t\t\twaitingRevive = true", SURV),
    ("V7 never over", TP, "\tif liveSides(g) == 0 then\n\t\tg.phase = \"over\"\n\tend\n", "", SURV),
    ("V8 the leaving shot stays", TP, "\tside.waiting = table.create(f.config.rows * f.config.cols, false)\n\trun.shot = nil\n\trun.bombs = {}\n", "\tside.waiting = table.create(f.config.rows * f.config.cols, false)\n", SURV),
    ("V9 a second retire counts", TP, "\tif side == nil or side.out then\n\t\treturn false\n\tend\n\tside.out = true", "\tif side == nil then\n\t\treturn false\n\tend\n\tside.out = true", SURV),
    ("V11 the out player's bunkers renewed each wave", TP, "\t\t\tside.waiting = table.create(fc.rows * fc.cols, true)\n\t\tend\n", "\t\t\tside.waiting = table.create(fc.rows * fc.cols, true)\n\t\telse\n\t\t\tside.run.barriers = Barriers.new(side.run.config.barriers)\n\t\tend\n", SURV),
    ("V12 a retire wipes the boards' numbers", TP, "\tside.out = true\n\tlocal run = side.run\n", "\tside.out = true\n\tlocal run = side.run\n\trun.lives = 0\n\trun.reason = nil\n\trun.revives = 0\n", SURV),
    ("V13 a retire moves the group", TP, "\tside.out = true\n\tlocal run = side.run\n", "\tside.out = true\n\tlocal run = side.run\n\trun.formation.x = 0\n", SURV),
    ("V14 a retire wipes the bunkers", TP, "\tside.out = true\n\tlocal run = side.run\n", "\tside.out = true\n\tlocal run = side.run\n\trun.barriers = { layout = run.barriers.layout, blocks = {} }\n", SURV),
    # The match (AC6)
    ("G1 the seed ignored", TP, "\tlocal s = if type(seed) == \"number\" then seed else 0\n", "\tlocal s = 0\n", MATCH),
    ("G2 arrivals leave holes in the flyers", TP, "\tlocal kept = {}\n\tfor _, fl in g.flyers do\n\t\tlocal _, _, _, _, arrived = TwoPlayer.flyerBox(g, fl)\n\t\tif arrived then\n\t\t\tlocal f = g.sides[fl.player].run.formation\n\t\t\tg.sides[fl.player].waiting[slotIndex(f, fl.row, fl.col)] = false\n\t\telse\n\t\t\ttable.insert(kept, fl)",
     "\tlocal kept = {}\n\tfor i, fl in g.flyers do\n\t\tlocal _, _, _, _, arrived = TwoPlayer.flyerBox(g, fl)\n\t\tif arrived then\n\t\t\tlocal f = g.sides[fl.player].run.formation\n\t\t\tg.sides[fl.player].waiting[slotIndex(f, fl.row, fl.col)] = false\n\t\telse\n\t\t\tkept[i] = fl", MATCH),
    ("G3 player 2 reads player 1's input", TP, "\treturn inputs[p]\nend", "\treturn inputs[1]\nend", MATCH),
    ("G4 the input not sanitized", TP, "\t\t\t\tlocal move, fire = Classic.sanitize(inputOf(inputs, p))\n", "\t\t\t\tlocal raw = inputOf(inputs, p) :: any\n\t\t\t\tlocal move = if type(raw) == \"table\" and type(raw.move) == \"number\" then raw.move else 0\n\t\t\t\tlocal fire = type(raw) == \"table\" and raw.fire ~= nil and raw.fire ~= false\n", MATCH),
]

# Correct variants: right changes of the kind f0218 (the view) and f0219 (boards, the revive offer) are expected to
# make, and f0216's own. Each must keep every spec green, f0216's included.
CV = [
    ("CV1 a hit says where", TP, "{ kind = \"AlienHit\", player = q, shooter = shooter, row = row, col = col, points = points }", "{ kind = \"AlienHit\", player = q, shooter = shooter, row = row, col = col, points = points, x = 0 } :: any", ALL),
    ("CV2 a side learns who plays it", TP, "{ run = Classic.new(s, c.pair), out = false, waiting = {} },", "{ run = Classic.new(s, c.pair), out = false, waiting = {}, who = 0 } :: any,", ALL),
    ("CV3 the match counts its ticks", TP, "\t\twave = 1,\n\t\tflyTick = 0,\n", "\t\twave = 1,\n\t\tticks = 0,\n\t\tflyTick = 0,\n", ALL),
    ("CV4 a landing event", TP, "\t\tif arrived then\n\t\t\tlocal f = g.sides[fl.player].run.formation\n", "\t\tif arrived then\n\t\t\t(g :: any).landed = ((g :: any).landed or 0) + 1\n\t\t\tlocal f = g.sides[fl.player].run.formation\n", ALL),
    ("CV5 a beat event beside the march", CL, "\t\teraseUnder(g)\n", "\t\teraseUnder(g)\n\t\ttable.insert(events, { kind = \"Beat\" })\n", ALL),
    ("CV6 a fly-in event each tick", TP, "\tif flying then\n\t\tadvanceFlyers(g)\n\tend\n", "\tif flying then\n\t\tadvanceFlyers(g)\n\t\ttable.insert(events, { kind = \"Flying\" })\n\tend\n", ALL),
    ("CV7 a flyer learns its kind", TP, "table.insert(flyers, { player = l.p, row = place[1], col = place[2], start = #flyers * gap })", "table.insert(flyers, { player = l.p, row = place[1], col = place[2], start = #flyers * gap, kind = 1 } :: any)", ALL),
]


def run(specs):
    return subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=900).stdout


def verdict(out, correct):
    lines = out.strip().splitlines()
    sums = [l for l in lines if " passed, " in l and " failed, " in l and "spec files" in l]
    last = sums[-1] if sums else (lines[-1] if lines else "NO OUTPUT")
    failed = "0 failed" not in last
    if correct:
        fails = [l.strip() for l in lines if l.startswith("FAIL ")]
        return ("ok (green)" if not failed else "RED: " + last + " " + "; ".join(fails)), not failed
    if not failed:
        return "SURVIVED", False
    msgs = [l for l in lines if l.startswith("     ")]
    if any("expected" in m for m in msgs) and not any(("attempt to" in m or "Unknown require" in m or "syntax" in m.lower()) for m in msgs):
        return "killed", True
    return "ERROR (not an assertion): " + (msgs[0].strip() if msgs else last), False


def git_show(ref, path):
    r = subprocess.run(["git", "-C", REPO, "show", f"{ref}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def f0216_files():
    for ref in F0216_REFS:
        names = subprocess.run(["git", "-C", REPO, "ls-tree", "-r", "--name-only", ref], capture_output=True, text=True).stdout.splitlines()
        patch = [n for n in names if n.endswith("/f0216/experiments/prototype.patch")]
        if not patch:
            continue
        folder = patch[0][: -len("experiments/prototype.patch")]
        specs = {n: git_show(ref, folder + "acceptance/" + n + ".spec.luau") for n in F0216_SPECS}
        if all(specs.values()):
            return ref, git_show(ref, patch[0]), specs
    sys.exit("refusing: f0216's prototype and specs are not on any of " + ", ".join(F0216_REFS))


def main():
    ref, patch, specs = f0216_files()
    got_patch = hashlib.sha256(patch).hexdigest()
    got_specs = hashlib.sha256(b"".join(specs[n] for n in F0216_SPECS)).hexdigest()
    if got_patch != F0216_PATCH_SHA or got_specs != F0216_SPECS_SHA:
        sys.exit(f"refusing: f0216's prototype or specs on {ref} moved since this base was cut; re-cut prototype.patch")
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    if os.path.exists(os.path.join(HOME, "src/shared/Logic/Classic/init.luau")):
        sys.exit("refusing: Classic already exists in the clone (f0216 is implemented); re-cut prototype.patch on it")
    item = os.path.join(HOME, ".tracker", "issues", "f0217")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    theirs = os.path.join(HOME, ".tracker", "issues", "f0216", "acceptance")
    os.makedirs(theirs, exist_ok=True)
    for n in F0216_SPECS:
        open(os.path.join(theirs, n + ".spec.luau"), "wb").write(specs[n])
    base = os.path.join(TMP, "f0216.patch")
    open(base, "wb").write(patch)
    subprocess.run(["git", "-C", CLONE, "apply", base], check=True)
    subprocess.run(["git", "-C", CLONE, "apply", os.path.join(HERE, "prototype.patch")], check=True)
    only = sys.argv[1:]
    msg, good = verdict(run(ALL), True)
    print("intended (f0217's and f0216's specs)".ljust(52), msg, flush=True)
    if not good:
        return 1
    bad = 0
    for entry in M + CV:
        mid, rel, old, new, specs_for = entry[:5]
        extra = entry[5] if len(entry) > 5 else []
        if only and not any(mid.startswith(o) for o in only):
            continue
        f = os.path.realpath(os.path.join(HOME, rel))
        if not f.startswith(TMP + os.sep):
            sys.exit(f"refusing to write outside the clone: {f}")
        src = open(f).read()
        edited, anchors = src, True
        for o, n in [(old, new)] + extra:
            if edited.count(o) != 1:
                print(mid.ljust(52), "ANCHOR", edited.count(o), repr(o[:50]), flush=True)
                anchors = False
                break
            edited = edited.replace(o, n)
        if not anchors:
            bad += 1
            continue
        open(f, "w").write(edited)
        try:
            msg, good = verdict(run(specs_for), mid.startswith("CV"))
        finally:
            open(f, "w").write(src)
        if not good:
            bad += 1
        print(mid.ljust(52), msg, flush=True)
    print(f"{len(M)} mutants, {len(CV)} correct variants, {bad} not as intended")
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        code = main()
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    sys.exit(code)
