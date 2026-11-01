#!/usr/bin/env python3
"""f0148's mutation check: applies each Rules-and-mutants row's mutant to the prototype, runs that row's spec file and
requires a failure on an assertion (not a load error), then restores the file. Also runs the correct variants, which
must stay green.

Usage: mutants.py <prototype pickman dir> [ids...]
The prototype is .worktree/proto-f0148 (origin/main + f0109's R0056 + f0126's and f0147's prototype patches +
f0147's narrowings + f0148, experiments/prototype.patch); its tree must be clean in src/. The specs are read from the prototype's
.tracker/issues/f0148/acceptance (copied there from the prep worktree)."""
import subprocess
import sys

L = "src/shared/Logic/"
A = ".tracker/issues/f0148/acceptance/"
B = L + "Best/init.luau"

MUTANTS = {
    "B1": (B, "	if type(raw) ~= \"table\" or not whole(raw.best) then", "	if type(raw) ~= \"table\" then", "best"),
    "B2": (B, "	if whole(requested) and requested <= best then", "	if whole(requested) and requested <= best + 1 then", "best"),
    "B3": (B, "	local best = if whole(level) then math.max(r.best, level) else r.best", "	local best = if whole(level) then level else r.best", "best"),
    "B4": (B, "	return { best = r.best, next = Best.valid(requested, r.best) or 1 }", "	return { best = r.best, next = if type(requested) == \"number\" then requested else 1 }", "best"),
    "B4b": (B, "	return { best = r.best, next = Best.valid(requested, r.best) or 1 }", "	return { best = r.best, next = Best.valid(requested, r.best) or r.best }", "best"),
    "B11": (B, "	return if raised.best > r.best then raised else nil", "	return raised", "adapters"),
    "B5": (B, "	return start or 1, { best = r.best }", "	return start or 1, { best = r.best, next = r.next }", "best"),
    "B6": (B, "	local start = if r.next then Best.valid(r.next, r.best) else nil", "	local start = r.next", "best"),
    "B7": (B, "	return { shown = b >= 2, level = level, down = level > 1, up = level < b }", "	return { shown = b >= 1, level = level, down = level > 1, up = level < b }", "best"),
    "B8": (B, "	local level = Best.valid(chosen, b) or b", "	local level = Best.valid(chosen, b) or 1", "best"),
    "B9": (B, "	return math.clamp(p.level + (if delta < 0 then -1 elseif delta > 0 then 1 else 0), 1, math.max(1, best))", "	return p.level + (if delta < 0 then -1 elseif delta > 0 then 1 else 0)", "best"),
    "B10": (B, "Best.KEYS = table.freeze({ Left = -1, Right = 1 })", "Best.KEYS = table.freeze({ Left = -1, Right = 1, A = -1, D = 1 })", "best"),
    "S1": (L + "Session/init.luau", "Game.new(s.config.play or Game.IMMEDIATE_CONFIG, s.config.ramp, start)", "Game.new(s.config.play or Game.IMMEDIATE_CONFIG, s.config.ramp)", "session"),
    "S2": (L + "Session/init.luau", "ramp = s.config.ramp, level = start }", "ramp = s.config.ramp }", "session"),
    "S3": (L + "Game/init.luau", "= g.start, 0, g.config.lives, 0, false", "= 1, 0, g.config.lives, 0, false", "session"),
    "S4": (L + "Game/init.luau", "if not isWhole(first) or first < 1 or first == math.huge then", "if false then", "session"),
    "S5": (L + "Game/init.luau", "if not isWhole(first) or first < 1 or first == math.huge then", "if not isWhole(first) or first < 1 then", "session"),
    "L1": (L + "Lobby/init.luau", "text = if level then `START LEVEL {level}` else \"START GAME\"", "text = \"START GAME\"", "lobby"),
    "L2": ("src/lobby/client/LobbyView.luau", "		if level then\n			startGame:FireServer(level)", "		if false then\n			startGame:FireServer(level)", "lobby"),
    "L3": ("src/lobby/client/LobbyView.luau", "	p.changed(function()\n		if refresh then\n			refresh()\n		end\n	end)", "	p.changed(function() end)", "lobby"),
    "L4": ("src/lobby/server/Starts.luau", [
        ("			local store = choose\n			if store then\n				store(player, level)\n			end\n			local ok", "			local ok"),
        ("			if ok then\n				Travel.answered", "			if choose then\n				(choose :: any)(player, level)\n			end\n			if ok then\n				Travel.answered"),
    ], "lobby"),
    "L5": ("src/lobby/server/Starts.luau", "		local answer, ticket = Travel.request(travel, id, os.clock())", "		if choose then\n			(choose :: any)(player, requested)\n		end\n		local answer, ticket = Travel.request(travel, id, os.clock())", "lobby"),
    "L6": ("src/lobby/client/LobbyPicker.luau", "			b.Visible = p.shown", "			b.Visible = true", "lobby"),
    "L7": ("src/lobby/client/LobbyPicker.luau", "				Enum.ContextActionPriority.High.Value,", "				Enum.ContextActionPriority.Default.Value,", "lobby"),
    "L7b": ("src/lobby/client/LobbyPicker.luau", "						return Enum.ContextActionResult.Pass", "						return Enum.ContextActionResult.Sink", "lobby"),
    "L10": ("src/lobby/server/Starts.luau", "			local level = held[player]", "			local level = requested", "lobby"),
    "L11": ("src/lobby/server/Starts.luau", "			held[player] = nil\n			local store", "			local store", "lobby"),
    "L8": ("src/lobby/client/LobbyPicker.luau", "		b.Size = UDim2.new(0.1, Lobby.BUTTON_MIN_PX, 0.12, Lobby.BUTTON_MIN_PX)", "		b.Size = UDim2.new(0.1, 0, 0.12, 0)", "lobby"),
    "L9": ("src/lobby/client/LobbyPicker.luau", "			player:GetAttributeChangedSignal(Best.ATTRIBUTE):Connect(render)", "			-- no listening for the best", "lobby"),
    "A1": ("src/lobby/server/Bests.luau", "			player:SetAttribute(Best.ATTRIBUTE, Best.decode(raw).best)", "			player:SetAttribute(Best.ATTRIBUTE, 1)", "adapters"),
    "A2": ("src/lobby/server/Bests.luau", "			return Best.choose(Best.decode(raw), requested)", "			return { best = Best.decode(raw).best, next = requested }", "adapters"),
    "A3": ("src/server/Bests.luau", "				return kept", "				return raw", "adapters"),
    "A4": ("src/server/Bests.luau", "	while starts[player] == nil and waited < Bests.WAIT and player.Parent ~= nil do", "	while false do", "adapters"),
    "A5": ("src/server/Bests.luau", "		if e.kind == \"Ready\" and e.reason == \"level\" and type(e.player) == \"string\" then", "		if e.kind == \"Ready\" and type(e.player) == \"string\" then", "adapters"),
    "A6": ("src/server/Sessions.luau", "			local start = if startOf then startOf(player) else nil", "			local start = nil", "adapters"),
    "A7": ("src/server/Sessions.luau", "				for _, fn in listeners do\n					fn(events)\n				end\n				local here", "				local here", "adapters"),
    "A8": ("src/server/Sessions.luau", "			if sessions[player] ~= nil or player.Parent == nil then", "			if player.Parent == nil then", "adapters"),
    "A9": ("src/server/Main.server.luau", "Sessions.listen(Bests.reached)\n", "", "adapters"),
    "A10": ("src/lobby/server/Main.server.luau", "Starts.choosing(Bests.choose)\n", "", "adapters"),
    "A12": ("src/server/Bests.luau", "		local ok, s = pcall(function(): DataStore\n			return DataStoreService:GetDataStore(Best.STORE)\n		end)", "		local ok, s = true, DataStoreService:GetDataStore(Best.STORE)", "adapters"),
    "A13": ("src/lobby/server/Bests.luau", "		local ok, s = pcall(function(): DataStore\n			return DataStoreService:GetDataStore(Best.STORE)\n		end)", "		local ok, s = true, DataStoreService:GetDataStore(Best.STORE)", "adapters"),
    "A14": ("src/server/Sessions.luau", "			for _, fn in made do\n				fn(player, s)\n			end", "", "adapters"),
    "S6": (L + "Game/init.luau", "g.score >= c.extraLifeScore * g.start then", "g.score >= c.extraLifeScore * g.level then", "session"),
    "S7": (L + "Game/init.luau", "= g.start, 0, g.config.lives, 0, false", "= g.level, 0, g.config.lives, 0, false", "session"),
    "A11": ("src/server/Bests.luau", "		starts[player] = if ok then start else 1", "		starts[player] = start", "adapters"),
}

VARIANTS = {
    # a later issue keeps the claim but reads the best first (a GetAsync before UpdateAsync is not needed): a no-op here
    "C1": (B, "	return start or 1, { best = r.best }", "	local kept: Record = { best = r.best }\n	return start or 1, kept", None),
}

SPECS = {k: A + k + ".spec.luau" for k in ("best", "session", "lobby", "adapters", "docs")}


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
            outs = [run(SPECS[k]) for k in ("best", "session", "lobby", "adapters")]  # docs reads game-design.md, not src
        finally:
            open(f"{home}/{file}", "w").write(original)
        green = all(" 0 failed" in o for o in outs)
        if not green:
            bad += 1
        print(f"{vid}: {'green' if green else 'RED'}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
