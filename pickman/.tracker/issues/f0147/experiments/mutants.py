#!/usr/bin/env python3
"""f0147's mutation check: applies each Rules-and-mutants row's mutant to the prototype, runs that row's spec file and
requires a failure on an assertion (not a load error), then restores the file. Also runs the correct variants, which
must stay green.

Usage: mutants.py <prototype pickman dir> [ids...]
The prototype is .worktree/proto-f0147 (origin/main + f0109's R0056 + f0126's prototype.patch + f0125's prototype diff
+ f0147, experiments/prototype.patch); its tree must be clean in src/. The specs are read from the prototype's
.tracker/issues/f0147/acceptance (copied there from the prep worktree)."""
import subprocess
import sys

L = "src/shared/Logic/"
A = ".tracker/issues/f0147/acceptance/"

# id: (file, old, new, spec)
MUTANTS = {
    "M1": (L + "Levels/init.luau", "first = 0.7,", "first = 0.75,", "ramp"),
    "M2": (L + "Levels/init.luau", "step = 1.05,", "step = 1.04,", "ramp"),
    "M3": (L + "Levels/init.luau", "return r.first * r.step ^ (math.min(level, r.top) - 1)", "return r.first * r.step ^ (level - 1)", "ramp"),
    "M4": (L + "Levels/init.luau", "local f = if ramp then Levels.rampFactor(ramp, level) else 1", "local f = 1", "ramp"),
    "M5": (L + "Ghosts/init.luau", 'return math.min(Levels.ghostSpeed(input.baseSpeed, input.level, "eyes", set.tuning, set.ramp), UNITS)', 'return Levels.ghostSpeed(input.baseSpeed, input.level, "eyes", set.tuning, set.ramp)', "ramp"),
    "M6": (L + "Session/init.luau", 'eyes = math.min(Levels.ghostSpeed(base, level, "eyes", k, r), Movement.UNITS)', 'eyes = Levels.ghostSpeed(base, level, "eyes", k, r)', "ramp"),
    "M7": (L + "Levels/init.luau", "local one = ROWS[1]", "local one = ROWS[math.min(n, #ROWS)]", "ramp"),
    "M8": (L + "Ghosts/init.luau", 'return Levels.ghostSpeed(input.baseSpeed, input.level, kind, set.tuning, set.ramp)', 'return Levels.ghostSpeed(input.baseSpeed, input.level, kind, set.tuning)', "ramp"),
    "M9": (L + "Ghosts/init.luau", "local schedule = Levels.schedule(input.level, input.tickRate, set.ramp)", "local schedule = Levels.schedule(input.level, input.tickRate)", "ramp"),
    "M9b": (L + "Ghosts/init.luau", "Levels.row(set.level, set.ramp).dotLimits", "Levels.row(set.level).dotLimits", "ramp"),
    "M9c": (L + "Ghosts/init.luau", "if set.frightened > 0 and set.frightened <= Levels.row(set.level, set.ramp).flashes", "if set.frightened > 0 and set.frightened <= Levels.row(set.level).flashes", "ramp"),
    "M10": (L + "Game/init.luau", "Levels.frightenedTicks(g.level, g.config.tickRate, g.ramp)", "Levels.frightenedTicks(g.level, g.config.tickRate)", "levels"),
    "M11": (L + "Hud/init.luau", "local total = play.power or Levels.frightenedTicks(play.level, Session.TICK_RATE)", "local total = Levels.frightenedTicks(play.level, Session.TICK_RATE)", "hud"),
    "M12": (L + "Session/init.luau", "power = Levels.frightenedTicks(play.level, Session.TICK_RATE, s.config.ramp),", "power = Levels.frightenedTicks(play.level, Session.TICK_RATE),", "hud"),
    "M13": (L + "Session/init.luau", "if s.config.ramp == nil and Pellets.remaining(member.pellets) == 0 then", "if Pellets.remaining(member.pellets) == 0 then", "levels"),
    "M14": (L + "Session/init.luau", "if s.config.ramp == nil and Pellets.remaining(member.pellets) == 0 then", "if false and Pellets.remaining(member.pellets) == 0 then", "levels"),
    "M15": (L + "Session/init.luau", "if ramp and member.levelPicks >= ramp.picks then", "if ramp and member.levelPicks > ramp.picks then", "levels"),
    "M16": (L + "Session/init.luau", "	member.longHops = false\n	member.levelPicks = 0", "	member.longHops = false", "levels"),
    "M17": (L + "Session/init.luau", "				teleport(s, member, s.tick)\n", "				teleport(s, member, s.tick)\n				member.levelPicks = 0\n", "levels"),
    "M18": (L + "Session/init.luau", "		member.picks.fast += 1\n		member.bonanza = true", "		member.picks.fast += 1\n		member.bonanza = true\n		Picks.roll(member.picks)\n		member.longHops = true", "levels"),
    "M19": (L + "Session/init.luau", "		member.picks.fast += 1\n		member.bonanza = true", "		member.bonanza = true", "levels"),
    "M20": (L + "Session/init.luau", "		if Blaster.gain(member.blaster) then\n			table.insert(out, { kind = \"ShotGained\", player = id })\n		end\n		for _, e in Game.cleared", "		for _, e in Game.cleared", "levels"),
    "M21": (L + "Session/init.luau", "member.longHops, member.bonanzaPill = true, true", "member.bonanzaPill = true", "levels"),
    "M22": (L + "Session/init.luau", "for _, e in Game.power(member.play, Picks.LONG_PILL_FACTOR) do\n				table.insert(out, tagged(id, e))\n			end\n		end\n		-- a pick", "for _, e in Game.power(member.play, 1) do\n				table.insert(out, tagged(id, e))\n			end\n		end\n		-- a pick", "levels"),
    "M23": (L + "Session/init.luau", "member.longHops, member.bonanzaPill = true, true", "member.longHops, member.bonanzaPill = true, false\n					member.play.frightened = 360\n					if member.ghosts then Ghosts.power(member.ghosts, 360) end", "levels"),
    # M24 (the new run clears a pending bonanza) is an equivalent mutant: a run cannot end between the tenth pick and
    # the next level's READY, so the prototype has no such clear (Rules and mutants)
    "M25": (L + "Session/init.luau", "local points = Game.points(member.play, Pellets.points(kind))", "local points = Pellets.points(kind)", "levels"),
    "M26": (L + "Session/init.luau", "		local points = Game.points(member.play, Ghosts.eat(set, name))\n		local event: Event", "		local points = Ghosts.eat(set, name)\n		local event: Event", "levels"),
    "M27": (L + "Session/init.luau", "	local points = Game.points(member.play, Ghosts.eat(set, name))\n	table.insert(out, { kind = \"Shot\"", "	local points = Ghosts.eat(set, name)\n	table.insert(out, { kind = \"Shot\"", "levels"),
    "M28": (L + "Game/init.luau", "return if g.ramp then points * g.level else points", "return points * g.level", "levels"),
    "M29": (L + "Game/init.luau", "g.score >= c.extraLifeScore * g.start then", "g.score >= c.extraLifeScore then", "levels"),
    "M30": (L + "Game/init.luau", "= g.start, 0, g.config.lives, 0, false", "= 1, 0, g.config.lives, 0, false", "levels"),
    "M31": (L + "Hud/init.luau", "`PICKS {play.picks}/{play.picksGoal}`", "`PICKS {play.picks}`", "hud"),
    "M32": (L + "Hud/init.luau", "return { x = score.x, y = score.y + score.h, w = score.w, h = score.h }", "return { x = score.x + score.w + 4 * score.h, y = score.y + score.h, w = score.w, h = score.h }", "hud"),
    "M33": ("src/client/HudView.luau", "picks.Visible = m.picks ~= nil", "picks.Visible = true", "hud"),
    "M34": (L + "Levels/init.luau", "	local r = Levels.row(level, ramp)\n	return round(baseSpeed * (if frightened", "	local r = Levels.row(level)\n	return round(baseSpeed * (if frightened", "levels"),
    "M35": (L + "Session/init.luau", 'Levels.ghostSpeed(s.config.movement.speed, member.play.level, "normal", tuning, s.config.ramp)', 'Levels.ghostSpeed(s.config.movement.speed, member.play.level, "normal", tuning)', "levels"),
    "M36": (L + "Session/init.luau", "	if c.ramp then\n		Levels.validateRamp(c.ramp)\n	end\n", "", "ramp"),
    "M37": (L + "Session/init.luau", "local last = if ramp then ramp.top else Levels.COUNT", "local last = Levels.COUNT", "ramp"),
    "M38": (L + "Levels/init.luau", "copy.frightSpeedFactor = one.frightSpeedFactor * f", "copy.frightSpeedFactor = one.frightSpeedFactor", "ramp"),
    "M39": (L + "Session/init.luau", "	local r = c.ramp\n	return {", "	local r = nil\n	return {", "ramp"),
    "M40": (L + "Session/init.luau", "	ramp = Levels.RAMP, -- levels by picked walls", "	-- ramp = Levels.RAMP, -- levels by picked walls", "ramp"),
    "M44": ("src/client/HudView.luau", 'local pl = label("Picks", Enum.TextXAlignment.Left, gui)', 'local pl = label("Picks", Enum.TextXAlignment.Right, gui)', "hud"),
    "M45": ("src/client/HudView.luau", "local box = Hud.picksBox(blocks.score)", "local box = Hud.picksBox(blocks.level)", "hud"),
    "M46": (L + "Ghosts/init.luau", "	if set.ramp and kind ~= \"normal\" then", "	if false and set.ramp and kind ~= \"normal\" then", "ramp"),
    "M47": (L + "Ghosts/init.luau", "	if set.ramp and kind ~= \"normal\" then", "	if set.ramp and kind == \"frightened\" then", "ramp"),
    "M48": (L + "Ghosts/init.luau", "		g.carry = total - units", "		g.carry = 0", "ramp"),
    "M49": (L + "Session/init.luau", 'tunnel = Levels.ghostRate(base, level, "tunnel", k, r)', 'tunnel = Levels.ghostSpeed(base, level, "tunnel", k, r)', "ramp"),
    "M26b": (L + "Session/init.luau", "		local points = Game.points(member.play, Ghosts.eat(set, name))\n		local event: Event", "		local points = Ghosts.eat(set, name) * member.play.level\n		local event: Event", "levels"),
    "M27b": (L + "Session/init.luau", "	local points = Game.points(member.play, Ghosts.eat(set, name))\n	table.insert(out, { kind = \"Shot\"", "	local points = Ghosts.eat(set, name) * member.play.level\n	table.insert(out, { kind = \"Shot\"", "levels"),
    # the level's last pick finishing after the ghosts' step (two edits)
    "M50": (L + "Session/init.luau", [
        ("		local pick = member.pick\n		if pick and s.tick >= pick.started + pick.ticks then\n			finishPick(s, id, member, out)", "		local pick = member.pick\n		local finishLate = pick and s.tick >= pick.started + pick.ticks\n		if false then\n			finishPick(s, id, member, out)"),
        ("			stepGhosts(s, id, member, playerPrev, ghostsPrev, before, out)\n", "			stepGhosts(s, id, member, playerPrev, ghostsPrev, before, out)\n		end\n		if finishLate and member.pick then\n			finishPick(s, id, member, out)\n"),
    ], "levels"),
    "M51": (L + "Game/init.luau", "g.score >= c.extraLifeScore * g.start then", "g.score >= c.extraLifeScore * g.level then", "levels"),
    # the count taken when a pick starts, not when it finishes (two edits)
    "M52": (L + "Session/init.luau", [
        ("	member.levelPicks += 1\n	local ramp = s.config.ramp", "	local ramp = s.config.ramp"),
        ("	member.armed = 0\n	member.pick = {", "	member.armed = 0\n	member.levelPicks += 1\n	member.pick = {"),
    ], "levels"),
    "M53": (L + "Ghosts/init.luau", [
        ("		local total = (g.carry or 0.5)", "		local total = (g.carry or 0)"),
        ("		carry = 0.5, -- f0147", "		carry = 0, -- f0147"),
    ], "ramp"),
    # one carry per ghost name, shared by every set (two edits)
    "M54": (L + "Ghosts/init.luau", [
        ("local function speedOf(set: Set, g: Ghost, input: Input): number", "local SHARED: { [string]: number } = {}\nlocal function speedOf(set: Set, g: Ghost, input: Input): number"),
        ("local total = (g.carry or 0.5)", "local total = (SHARED[g.name] or 0.5)"),
        ("		g.carry = total - units", "		SHARED[g.name] = total - units"),
    ], "ramp"),
    "M55": (L + "Levels/init.luau", "if not whole(r.top) or r.top > Levels.MAX_TOP then", "if not whole(r.top) then", "ramp"),
    # the carries kept over a new level or a new run (saved before the ghosts are placed again, restored after)
    "M58": (L + "Ghosts/init.luau", [
        ("		set.house.personal = { pinky = 0, inky = 0, clyde = 0 }\n		set.house.global = nil\n	end\n	place(set)", "		set.house.personal = { pinky = 0, inky = 0, clyde = 0 }\n		set.house.global = nil\n	end\n	local kept = {}\n	for _, g in set.ghosts do\n		kept[g.name] = g.carry\n	end\n	place(set)\n	if reason ~= \"respawn\" then\n		for _, g in set.ghosts do\n			g.carry = kept[g.name]\n		end\n	end"),
    ], "ramp"),
    "M59": (L + "Ghosts/init.luau", "	set.frightened = ticks\n	set.chain = 0\n", "	set.frightened = ticks\n	set.chain = 0\n	for _, g in set.ghosts do\n		g.carry = 0.5\n	end\n", "ramp"),
    "M60": (L + "Ghosts/init.luau", "	if set.ramp and kind ~= \"normal\" then", "	if kind == \"normal\" then\n		g.carry = 0.5\n	end\n	if set.ramp and kind ~= \"normal\" then", "ramp"),
    "M61": (L + "Session/init.luau", "picksGoal = if s.config.ramp then s.config.ramp.picks else nil,", "picksGoal = if s.config.ramp then 10 else nil,", "hud"),
    "M62": (L + "Session/init.luau", "				member.bonanza = false", "				member.bonanza = false\n				if e.reason == \"respawn\" and member.longHops then\n					member.bonanzaPill = true\n				end", "levels"),
    "M63": (L + "Session/init.luau", "	local boon: Picks.Boon = Picks.roll(member.picks)", "	local boon: Picks.Boon = Picks.roll(member.picks)\n	while boon == \"jumps\" and member.longHops do\n		boon = Picks.roll(member.picks)\n	end", "levels"),
    "M41": (L + "Hud/init.luau", 'bonanza = "BONANZA!"', 'bonanza = "BONUS"', "hud"),
    "M42": (L + "Session/init.luau", "then Ghosts.new(s.maze, s.seed, { tuning = s.config.ghostTuning, ramp = s.config.ramp })", "then Ghosts.new(s.maze, s.seed, { tuning = s.config.ghostTuning })", "ramp"),
    "M43": (L + "Session/init.luau", "			picks = if s.config.ramp then s.members[id].levelPicks else nil,", "			picks = s.members[id].levelPicks,", "levels"),
}

# correct variants: right changes of the kind later issues make; every spec must stay green
VARIANTS = {
    # f0148 starts a run on a level above 1: Game.new keeps start = 1 unless told otherwise
    "C1": (L + "Game/init.luau", "		ramp = ramp,\n		start = 1,", "		ramp = ramp,\n		start = math.max(1, 1),", None),
    # the bonanza's grants in another order (shot before the fast pick)
    "C2": (L + "Session/init.luau", "		member.picks.fast += 1\n		member.bonanza = true", "		member.bonanza = true\n		member.picks.fast += 1", None),
}

SPECS = {k: A + k + ".spec.luau" for k in ("ramp", "levels", "hud", "docs")}


def run(spec: str) -> str:
    r = subprocess.run(["lune", "run", "tests/run", "--", spec], capture_output=True, text=True, timeout=600)
    return r.stdout + r.stderr


def apply(home: str, file: str, old, new=None) -> str:
    """Applies one (old, new) replacement, or a list of them when `old` is a list of pairs; returns the original."""
    path = f"{home}/{file}"
    text = open(path).read()
    pairs = old if isinstance(old, list) else [(old, new)]
    out = text
    for o, n in pairs:
        if out.count(o) != 1:
            raise SystemExit(f"{file}: the mutant's text is found {out.count(o)} times, not once:\n{o}")
        out = out.replace(o, n)
    open(path, "w").write(out)
    return text


def main():
    home = sys.argv[1]
    want = set(sys.argv[2:])
    import os
    os.chdir(home)
    dirty = subprocess.run(["git", "status", "--porcelain", "--", "src"], capture_output=True, text=True).stdout
    if dirty.strip():
        raise SystemExit("the prototype's src/ is not clean")
    bad = 0
    for mid, entry in MUTANTS.items():
        if want and mid not in want:
            continue
        if len(entry) == 3:
            file, pairs, spec = entry
            original = apply(home, file, pairs)
        else:
            file, old, new, spec = entry
            original = apply(home, file, old, new)
        try:
            out = run(SPECS[spec])
        finally:
            open(f"{home}/{file}", "w").write(original)
        failed = "FAIL" in out and " 0 failed" not in out
        load = "could not load" in out or "error while loading" in out
        status = "killed" if failed and not load else ("LOAD ERROR" if load else "SURVIVED")
        if status != "killed":
            bad += 1
        print(f"{mid}: {status} ({spec})")
    for vid, (file, old, new, _) in VARIANTS.items():
        if want and vid not in want:
            continue
        original = apply(home, file, old, new)
        try:
            outs = [run(SPECS[k]) for k in ("ramp", "levels", "hud")]  # docs reads game-design.md, not src
        finally:
            open(f"{home}/{file}", "w").write(original)
        green = all(" 0 failed" in o for o in outs)
        if not green:
            bad += 1
        print(f"{vid}: {'green' if green else 'RED'}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
