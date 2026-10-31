#!/usr/bin/env python3
"""d0149 prep mutation check. Run from the prototype's pickman/ home (proto-d0149): applies each mutant of the
issue's Rules and mutants table to one source file, runs the row's spec from .cache/d0149/acc, and requires a FAIL
on an assertion (a load or syntax error does not count). Restores each file with git afterwards. Then runs the
unmutated tree and requires every spec to pass. Usage: python3 mutants.py <acceptance dir copied under .cache>."""
import subprocess, sys

ACC = sys.argv[1] if len(sys.argv) > 1 else ".cache/d0149/acc"
T = "src/shared/Logic/Touch/init.luau"
V = "src/shared/Logic/View/init.luau"
C = "src/client/Controls.luau"
K = "src/client/Camera.luau"
H = "src/client/HudView.luau"
M = "src/client/Main.client.luau"

# id, file, old, new, spec
MUTANTS = [
    ("S1", T, "local s, emitted = Pad.steer(f.steer, px, py)", "local s, emitted = Pad.steer(Pad.steerStart(), px, py)", "fold"),
    ("S2", T, "local px, py = (x - c.x) / c.r, (c.y - y) / c.r", "local px, py = (x - c.x) / c.r, (y - c.y) / c.r", "fold"),
    ("S3", T, "	if len > 1 then\n		return px / len, py / len\n	end", "", "fold"),
    ("S4", T, "f.steer = steerTo(f, ctx.steer)", "local _ = f", "fold"),
    ("Z1", T, "	if inRect(ctx.fire, x, y) then\n		return \"fire\"\n	end\n	if inRect(ctx.pick, x, y) then\n		return \"pick\"\n	end\n	if inCircle(ctx.steer, x, y) then\n		return \"steer\"\n	end",
     "	if inCircle(ctx.steer, x, y) then\n		return \"steer\"\n	end\n	if inCircle(ctx.look, x, y) then\n		return \"look\"\n	end\n	if inRect(ctx.fire, x, y) then\n		return \"fire\"\n	end\n	if inRect(ctx.pick, x, y) then\n		return \"pick\"\n	end", "fold"),
    ("Z2", T, "return dx * dx + dy * dy < c.r * c.r", "return dx * dx + dy * dy <= c.r * c.r", "fold"),
    ("Z3", T, "return dx * dx + dy * dy < c.r * c.r", "return math.abs(dx) < c.r and math.abs(dy) < c.r", "fold"),
    ("Z4", T, "	if inCircle(ctx.look, x, y) then\n		return \"look\"\n	end\n	return nil", "	return \"look\"", "fold"),
    ("L1", T, "local q = math.atan2(-x, y) / (math.pi / 2)", "local q = math.atan2(x, y) / (math.pi / 2)", "fold"),
    ("L2", T, "return if q <= -2 then q + 4 else q", "return q", "fold"),
    ("L3", T, "Touch.LOOK_DEAD = 0.25", "Touch.LOOK_DEAD = 0", "fold"),
    ("L4", T, "				table.insert(effects, { kind = \"point\", quarters = nil })\n", "", "fold"),
    ("P1", T, "if not far and t - finger.t0 < Touch.TAP_SECONDS then", "if not far and t - finger.t0 <= Touch.TAP_SECONDS then", "fold"),
    ("P2", T, "or distance(event.x, event.y, finger.x0, finger.y0) >= Touch.TAP_SLOP\n				if", "or distance(event.x, event.y, finger.x0, finger.y0) > Touch.TAP_SLOP\n				if", "fold"),
    ("P3", T, "local far = finger.far\n", "local far = false\n", "fold"),
    ("P4", T, "				table.insert(effects, { kind = \"pick\" })\n			elseif zone == \"steer\"", "				table.insert(effects, { kind = \"pick\" })\n			elseif zone == \"look\" then\n				table.insert(effects, { kind = \"hop\" })\n			elseif zone == \"steer\"", "fold"),
    ("P5", T, "Touch.TAP_SECONDS = 0.25", "Touch.TAP_SECONDS = 0.5", "fold"),
    ("F1", T, "			taken = taken or f.zone == zone", "			taken = taken", "fold"),
    ("F2", T, "			moved.far = finger.far or", "			moved.zone = Touch.zone(event.x, event.y, ctx) or finger.zone\n			moved.far = finger.far or", "fold"),
    ("F3", T, "local fingers: { [number]: Finger } = table.clone(state.fingers)", "local fingers: { [number]: Finger } = state.fingers", "fold"),
    ("B1", T, "Touch.CIRCLE_SHARE = 0.3", "Touch.CIRCLE_SHARE = 0.35", "fold"),
    ("B2", T, "Touch.CIRCLE_MIN = 96", "Touch.CIRCLE_MIN = 80", "fold"),
    ("B3", T, "local lookBottom = box.safeY + box.safeH - m - box.barHeight", "local lookBottom = box.safeY + box.safeH - 2 * m - box.barHeight", "clear"),
    ("B4", T, "local rowBottom = box.safeY + box.safeH - 2 * m - math.max(box.iconSize, box.barHeight)", "local rowBottom = box.safeY + box.safeH - 2 * m - box.barHeight", "clear"),
    ("B5", T, "pick = { x = fire.x - m - side, y = fire.y, w = side, h = side }", "pick = { x = fire.x - side, y = fire.y, w = side, h = side }", "fold"),
    ("B6", T, "Touch.BUTTON_SHARE = 0.45", "Touch.BUTTON_SHARE = 0.6", "clear"),
    ("B7", T, "local lookRight = box.safeX + box.safeW - m", "local lookRight = box.safeX + box.safeW", "fold"),
    ("K1", T, "		round(Touch.CIRCLE_SHARE * math.max(0, math.min(box.safeW, box.safeH))),", "		round(Touch.CIRCLE_SHARE * math.max(0, math.max(box.safeW, box.safeH))),", "fold"),
    ("N1", T, "			local p: Point = { x = c.x + px * c.r, y = c.y - py * c.r }", "			local p: Point = { x = f.x, y = f.y }", "fold"),
    ("C1", C, "			if effect.kind == \"turn\" then\n				intent:FireServer(effect.intent)", "			if effect.kind == \"turn\" then\n				local _ = effect.intent", "adapters"),
    ("C2", C, "touchTaps, pair = Boost.tap(touchTaps, os.clock())", "touchTaps, pair = Boost.taps(), false", "adapters"),
    ("C3", C, "				if k and k.point then\n					k.point(effect.quarters)\n				end", "", "adapters"),
    ("C4", C, "			k.point(nil) -- a look circle held when focus went springs back", "", "adapters"),
    ("C5", C, "			onKnobs(Touch.knobs(fingers, placed))", "			onKnobs({})", "adapters"),
    ("C6", C, "x = sx, y = sy, t = os.clock() }", "x = sx, y = sy }", "adapters"),
    ("C7", C, "			elseif effect.kind == \"hop\" then\n				intent:FireServer(Hop.INTENT)", "			elseif effect.kind == \"hop\" then\n				fire()", "adapters"),
    ("V1", V, "		local p = a.point\n		return if p ~= nil and finite(p) then p else nil", "		return nil", "look"),
    ("V2", V, "		return if p ~= nil and finite(p) then p else nil", "		return p", "look"),
    ("V3", V, "	if not (a.up or a.down or a.left or a.right) then\n		local p = a.point", "	if a.point ~= nil then\n		return a.point\n	end\n	if not (a.up or a.down or a.left or a.right) then\n		local p = a.point", "look"),
    ("A1", K, "	arrows = { up = a.up, down = a.down, left = a.left, right = a.right, point = arrows.point }", "	arrows = { up = a.up, down = a.down, left = a.left, right = a.right }", "adapters"),
    ("A2", K, "		{ up = arrows.up, down = arrows.down, left = arrows.left, right = arrows.right, point = quarters }", "		{ up = arrows.up, down = arrows.down, left = arrows.left, right = arrows.right }", "adapters"),
    ("H1", H, "	placeCircle(lookCircle, placed.look)", "", "adapters"),
    ("H2", H, "	f.Visible = UserInputService.TouchEnabled\n	f.BackgroundColor3 = WHITE\n	f.BackgroundTransparency = transparency", "	f.Visible = true\n	f.BackgroundColor3 = WHITE\n	f.BackgroundTransparency = transparency", "adapters"),
    ("H3", H, "	HudView.knobs({}) -- each knob at its circle's centre until a finger pulls it", "", "adapters"),
    ("H4", H, "			local p = at or { x = c.x, y = c.y }", "			local p = { x = c.x, y = c.y }", "adapters"),
    ("H5", H, "	place(pickButton, placed.pick, l.textSize)", "	place(pickButton, placed.fire, l.textSize)", "adapters"),
    ("H6", H, "local KNOB = 0.4", "local KNOB = 0.5", "adapters"),
    ("H7", H, "	stroke.Parent = f\n", "", "adapters"),
    ("H8", H, 'steerCircle = circle("Steer", 0.8, gui)', 'steerCircle = circle("Steer", 0.6, gui)', "adapters"),
    ("M1", M, "point = Camera.point", "point = nil", "adapters"),
    ("M2", M, "Controls.start(Camera.snap, Camera.holdMouse, HudView.buttons, HudView.knobs)", "Controls.start(Camera.snap, Camera.holdMouse, HudView.buttons)", "adapters"),
]

# correct variants: right changes of the kind the next issues make (f0145 boots another view from Main, f0147
# draws another HUD element, a later touch control adds an effect); every spec must stay green under each
CORRECT = [
    ("CV1", M, "PelletView.start()", "PelletView.start()\nlocal _offer = nil -- a further view booted here (f0145's kind)"),
    ("CV2", H, "	fireButton = button(", "	local extra = label(\"Extra\", Enum.TextXAlignment.Center, gui) -- f0147's kind\n	extra.Visible = false\n	fireButton = button("),
    ("CV3", C, "			elseif effect.kind == \"fire\" then", "			elseif (effect :: any).kind == \"later\" then\n				local _ = effect\n			elseif effect.kind == \"fire\" then"),
]


def run(spec):
    out = subprocess.run(["lune", "run", "tests/run", "--", f"{ACC}/{spec}.spec.luau"], capture_output=True, text=True)
    return out.stdout + out.stderr


def main():
    bad = []
    for spec in ["fold", "clear", "adapters", "look", "docs"]:
        o = run(spec)
        if " 0 failed" not in o:
            print(f"BASE {spec} not green:\n{o[-800:]}")
            sys.exit(1)
    for mid, path, old, new, spec in MUTANTS:
        src = open(path).read()
        if src.count(old) != 1:
            bad.append(f"{mid}: old text found {src.count(old)} times")
            continue
        open(path, "w").write(src.replace(old, new))
        try:
            o = run(spec)
        finally:
            subprocess.run(["git", "checkout", "--", path], check=True)
        loadfail = "could not load" in o or "SyntaxError" in o or "syntax error" in o.lower()
        if " 0 failed" in o:
            bad.append(f"{mid}: survived ({spec})")
        elif loadfail:
            bad.append(f"{mid}: killed only by a load error ({spec})")
        else:
            first = next((l for l in o.splitlines() if l.startswith("FAIL")), "")
            print(f"{mid}: killed :: {first.split(' :: ', 1)[-1][:90]}")
    for cid, path, old, new in CORRECT:
        src = open(path).read()
        if src.count(old) != 1:
            bad.append(f"{cid}: old text found {src.count(old)} times")
            continue
        open(path, "w").write(src.replace(old, new))
        try:
            outs = [run(spec) for spec in ["fold", "clear", "adapters", "look", "docs"]]
        finally:
            subprocess.run(["git", "checkout", "--", path], check=True)
        if all(" 0 failed" in o for o in outs):
            print(f"{cid}: green")
        else:
            bad.append(f"{cid}: a correct variant fails")
    print(f"{len(MUTANTS) - len([b for b in bad if not b.startswith('CV')])} of {len(MUTANTS)} killed on an assertion")
    for b in bad:
        print("  " + b)
    sys.exit(1 if bad else 0)


main()
