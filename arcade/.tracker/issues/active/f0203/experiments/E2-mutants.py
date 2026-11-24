# E2 (f0203 prep): the mutation check, in a throwaway clone only.
# Run from the top of a checkout, bounded:
#   ./zn run --time 3600 -- python3 -I arcade/.tracker/issues/f0203/experiments/E2-mutants.py
# It takes no argument naming where to work. It clones the repository this file sits in into a new temporary folder
# (git clone --no-hardlinks), applies prototype.patch there (the prep prototype of the four cores, against prep base
# d5743cb7), copies this issue's acceptance specs over the clone's (so the specs as they are now are the ones judged),
# writes into the clone's arcade/.tracker/architecture.md the section the Design gives verbatim (as the executor will),
# runs every spec once unmutated (each must pass), then applies each mutant, one at a time, to the clone's prototype
# and runs the named spec, which must fail on an assertion (not on a load error). The clone is removed at the end.
# Nothing outside the temporary folder is written.
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ISSUE = os.path.dirname(HERE)
TOP = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
REL_ISSUE = os.path.relpath(ISSUE, os.path.join(TOP, "arcade"))  # .tracker/issues/f0203
SPECS = ["rng", "pad", "touch", "look", "games", "place", "docs"]

# id, feature, old, new, spec. Each `old` must occur exactly once in the prototype.
M = [
    ("R1", "Rng", "multiplier = 48271, mix = 1", "multiplier = 16807, mix = 1", "rng"),
    ("R2", "Rng", "g.state = (g.state * g.multiplier) % MODULUS\n\treturn g.state % n + 1", "local o = g.state\n\tg.state = (g.state * g.multiplier) % MODULUS\n\treturn o % n + 1", "rng"),
    ("R3", "Rng", "\ts = s % (MODULUS - 1)\n", "", "rng"),
    ("R4", "Rng", "then math.floor(seed)\n\t\telse 0", "then math.floor(seed)\n\t\telse seed", "rng"),
    ("R6", "Rng", "return (g.state - 1) / (MODULUS - 1)", "return g.state / MODULUS", "rng"),
    ("R7", "Rng", "return Rng.int(g, n)", "return Rng.int(table.clone(g), n)", "rng"),
    ("R9", "Rng", "then math.floor(seed)\n", "then seed\n", "rng"),
    ("P1", "Pad", "if r >= t.on then\n\t\t\tlocal now = sector", "if r > t.on then\n\t\t\tlocal now = sector", "pad"),
    ("P2", "Pad", "\tif r < t.off then\n\t\treturn { held = nil }, nil\n\tend\n\tif r >= t.on and off(", "\tif r < t.on then\n\t\treturn { held = nil }, nil\n\tend\n\tif r >= t.on and off(", "pad"),
    ("P3", "Pad", "> 45 + t.margin + 1e-9", "> 45 + 1e-9", "pad"),
    ("P4", "Pad", "if math.abs(y) >= math.abs(x) then", "if math.abs(y) > math.abs(x) then", "pad"),
    ("P5", "Pad", "local r = math.abs(x)\n", "local r = math.sqrt(x * x + y * y)\n", "pad"),
    ("P5b", "Pad", "\tif now ~= s.held then\n", "\tif now ~= s.held and false then\n", "pad"),
    ("P5c", "Pad", "\t\t\treturn { held = now }, now\n\t\tend\n\t\treturn { held = nil }, nil\n\tend\n\treturn { held = s.held }, nil", "\t\t\treturn { held = now }, now\n\t\tend\n\t\treturn { held = s.held }, nil\n\tend\n\treturn { held = s.held }, nil", "pad"),
    ("P6", "Pad", "local a = scaled * scaled", "local a = scaled", "pad"),
    ("P6b", "Pad", "if r <= t.lookDead then", "if r < t.lookDead then", "pad"),
    ("P7", "Pad", "local dyaw = -a * (x / r)", "local dyaw = a * (x / r)", "pad"),
    ("P8", "Pad", "return dyaw, if t.invert then -dpitch else dpitch", "return if t.invert then -dyaw else dyaw, if t.invert then -dpitch else dpitch", "pad"),
    ("P9", "Pad", "magnitude >= t.off then", "magnitude >= t.on then", "pad"),
    ("P10", "Pad", "function Pad.steer(s: Steer, x: number, y: number, tuning: Tuning?): (Steer, Dir?)\n\tlocal t = tuning or Pad.DEFAULT", "function Pad.steer(s: Steer, x: number, y: number, tuning: Tuning?): (Steer, Dir?)\n\tlocal t = if tuning and tuning.axes == \"horizontal\" then tuning else Pad.DEFAULT", "pad"),
    ("P12", "Pad", "or not finite(dt) or dt <= 0 then", "then", "pad"),
    ("P13", "Pad", "if not finite(x) or not finite(y) then\n\t\treturn { held = nil }, nil", "if false then\n\t\treturn { held = nil }, nil", "pad"),
    ("P14", "Pad", "return n ~= nil and n >= 1 and n <= 8", "return n ~= nil", "pad"),
    ("T1", "Touch", "table.insert(effects, { kind = \"release\", name = finger.button })", "", "touch"),
    ("T2", "Touch", "for _, b in ctx.buttons do\n\t\tif Touch.inside", "for i = #ctx.buttons, 1, -1 do\n\t\tlocal b = ctx.buttons[i]\n\t\tif Touch.inside", "touch"),
    ("T3", "Touch", "x < r.x + r.w and y < r.y + r.h", "x <= r.x + r.w and y <= r.y + r.h", "touch"),
    ("T4", "Touch", "Touch.swipe(event.x - finger.x0, event.y - finger.y0)", "Touch.swipe(event.x - finger.x, event.y - finger.y)", "touch"),
    ("T5", "Touch", "< Touch.MIN_SWIPE then", "<= Touch.MIN_SWIPE then", "touch"),
    ("T6", "Touch", "math.rad(Touch.AXIS_DEGREES) + 1e-9", "math.rad(45) + 1e-9", "touch"),
    ("T7", "Touch", "taken = taken or same(f, button, side)", "taken = taken", "touch"),
    ("T8", "Touch", "local use: Use = if side == \"left\" then ctx.left else ctx.right", "local use: Use = if side == \"left\" then \"swipe\" else \"look\"", "touch"),
    ("T9", "Touch", "if bad and phase ~= \"end\" then", "if bad then", "touch"),
    ("T10", "Touch", "\ttable.sort(ids)\n", "\ttable.sort(ids, function(a, b) return a > b end)\n", "touch"),
    ("T11", "Touch", "local fingers: { [number]: Finger } = table.clone(state.fingers)", "local fingers: { [number]: Finger } = state.fingers", "touch"),
    ("T12", "Touch", "x < ctx.width / 2 then left else right", "x <= ctx.width / 2 then left else right", "touch"),
    ("T13", "Touch", "if button ~= nil or use ~= \"none\" then", "if true then", "touch"),
    ("T14", "Touch", "if dy > 0 then \"down\" else \"up\"", "if dy < 0 then \"down\" else \"up\"", "touch"),
    ("T15", "Touch", "if finger.button == nil and finger.use == \"look\" then", "if finger.button == nil then", "touch"),
    ("L1", "Look", "if r == -PI then\n\t\treturn PI\n\tend", "", "look"),
    ("L2", "Look", "local diff = Look.wrap(target - current)", "local diff = target - current", "look"),
    ("L3", "Look", "if current == nil or not finite(current) then\n\t\treturn Look.wrap(target)", "if current == nil or not finite(current) then\n\t\treturn 0", "look"),
    ("L4", "Look", "return (PI / 2) / t.turnSeconds", "return (PI / 2) / 0.12", "look"),
    ("L5", "Look", "yaw = Look.wrap(l.yaw - dx * k)", "yaw = Look.wrap(l.yaw + dx * k)", "look"),
    ("L6", "Look", "return math.clamp(p, -t.maxPitch, t.maxPitch)", "return p", "look"),
    ("L7", "Look", "if not finite(dx) or not finite(dy) then", "if false then", "look"),
    ("L7b", "Look", "if not finite(dyaw) or not finite(dpitch) then", "if false then", "look"),
    ("L8", "Look", "return side * 1.5", "return -side * 1.5", "look"),
    ("L9", "Look", "return { look = toward(prev.look, {", "return { look = toward(look, {", "look"),
    ("L10", "Look", "spring = not (back.yaw == 0 and back.pitch == 0)", "spring = true", "look"),
    ("L11", "Look", "if look.yaw ~= prev.look.yaw or look.pitch ~= prev.look.pitch then", "if false then", "look"),
    ("L12", "Look", "return math.clamp(a, 0, 1)\nend", "return a\nend", "look"),
    ("L13", "Look", "return Look.wrap(from + Look.wrap(to - from) * a)", "return Look.wrap(from + (to - from) * a)", "look"),
    ("L15", "Look", "return Look.rate(t) * (if finite(dt) and dt > 0 then dt else 0)", "return Look.rate(t) * dt", "look"),
    ("L16", "Look", "local ahead = (if a.up then 1 else 0) - (if a.down then 1 else 0)", "local ahead = (if a.up then 1 else 0)", "look"),
    ("G1", "Pad", "local Pad = {}\n", "local Pad = {}\nPad.BUTTONS = { ButtonA = \"Jump\" }\n", "games"),
    ("G2", "Touch", "local Touch = {}\n", "local Touch = {}\nTouch.snapRect = function() end\n", "games"),
    ("G3", "Pad", "\tif s.held == nil or s.held == \"up\" or s.held == \"down\" then\n\t\tif r >= t.on then\n\t\t\treturn { held = now }, now", "\tif s.held == nil or s.held == \"up\" or s.held == \"down\" then\n\t\tif r >= t.on then\n\t\t\treturn { held = nil }, now", "games"),
]


def refusal_mutants(feature: str, src: str):
    # one mutant per stated refusal: each `if <cond> then` whose next line raises, dropped; and for a range written as
    # `a or b`, each side dropped on its own
    out = []
    lines = src.split("\n")
    n = 0
    for i, line in enumerate(lines[:-1]):
        m = re.match(r"^\tif (.+) then$", line)
        if m and lines[i + 1].lstrip().startswith("error("):
            cond = m.group(1)
            n += 1
            out.append((f"{feature[0]}X{n}", feature, f"{line}\n{lines[i + 1]}", f"\tif false then\n{lines[i + 1]}", feature.lower()))
            parts = [p for p in cond.split(" or ")] if " or " in cond and not cond.startswith("not (") else []
            for j, p in enumerate(parts):
                rest = " or ".join(q for k, q in enumerate(parts) if k != j)
                out.append((f"{feature[0]}X{n}{'ab'[j]}", feature, f"{line}\n{lines[i + 1]}", f"\tif {rest} then\n{lines[i + 1]}", feature.lower()))
    return out


HEADING = "## Input and look cores (f0203)\n"
DEPS = "## Allowed dependencies\n"


def section_body() -> str:
    doc = open(os.path.join(ISSUE, "f0203.md")).read()
    a = doc.index("```markdown\n") + len("```markdown\n")
    return doc[a : doc.index("```\n", a)]


def with_section(arch: str) -> str:
    return arch.replace(DEPS, HEADING + section_body() + "\n" + DEPS, 1)


def drop_line(text: str, needle: str) -> str:
    return "\n".join(l for l in text.split("\n") if needle not in l)


# docs mutants: each a function of the architecture file as the executor leaves it
DOCS = [
    ("D1", "the section after the deps block", lambda t: t.replace(HEADING + section_body() + "\n", "", 1) + "\n" + HEADING + section_body()),
    ("D2", "the every-input bullet left out", lambda t: drop_line(t, "**Every game builds its input from these cores**")),
    ("D3", "the no-Logic-require bullet left out", lambda t: drop_line(t, "Game Logic never requires them")),
    ("D4", "the open cells left out", lambda t: drop_line(t, "**Open per game**")),
    ("D5", "the differences heading left out", lambda t: drop_line(t, "**Differences from pickman's copies (c0204)**")),
    ("D6", "the Touch difference left out", lambda t: drop_line(t, "  - Touch:")),
    ("D7", "the heading renamed", lambda t: t.replace(HEADING, "## Input cores\n", 1)),
]


def run(spec_path: str, cwd: str) -> str:
    r = subprocess.run(["lune", "run", "tests/run", "--", spec_path], cwd=cwd, capture_output=True, text=True, timeout=300)
    return r.stdout + r.stderr


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="f0203-e2-")
    try:
        repo = os.path.join(tmp, "repo")
        subprocess.run(["git", "clone", "-q", "--no-hardlinks", TOP, repo], check=True)
        subprocess.run(["git", "-C", repo, "apply", os.path.join(HERE, "prototype.patch")], check=True)
        home = os.path.join(repo, "arcade")
        dst = os.path.join(home, REL_ISSUE, "acceptance")
        shutil.rmtree(dst, ignore_errors=True)
        shutil.copytree(os.path.join(ISSUE, "acceptance"), dst)
        acc = os.path.join(REL_ISSUE, "acceptance")
        arch_path = os.path.join(home, ".tracker", "architecture.md")
        arch = with_section(open(arch_path).read())
        open(arch_path, "w").write(arch)
        bad = 0
        for spec in SPECS:
            out = run(f"{acc}/{spec}.spec.luau", home)
            last = [l for l in out.splitlines() if "passed," in l]
            ok = bool(last) and " 0 failed" in last[-1]
            print(f"baseline {spec}: {last[-1] if last else out.strip()[-200:]}")
            bad += 0 if ok else 1
        mutants = list(M)
        for feat, fn in (("Rng", "Rng.new"), ("Pad", "Pad.tune"), ("Look", "Look.tune")):
            src = open(os.path.join(home, "src/shared/Logic", feat, "init.luau")).read()
            mutants += refusal_mutants(feat, src)
        killed = 0
        for mid, feat, old, new, spec in mutants:
            path = os.path.join(home, "src/shared/Logic", feat, "init.luau")
            src = open(path).read()
            if src.count(old) != 1:
                print(f"{mid}: NOT APPLIED (found {src.count(old)})")
                bad += 1
                continue
            open(path, "w").write(src.replace(old, new))
            try:
                out = run(f"{acc}/{spec}.spec.luau", home)
            finally:
                open(path, "w").write(src)
            fails = [l for l in out.splitlines() if l.startswith("FAIL")]
            if fails and "could not load" not in out:
                killed += 1
                print(f"{mid}: killed by {spec} :: {fails[0].split(' :: ', 1)[-1]}")
            else:
                bad += 1
                print(f"{mid}: SURVIVED ({'load error' if fails else 'no failure'})")
        for mid, what, fn in DOCS:
            open(arch_path, "w").write(fn(arch))
            try:
                out = run(f"{acc}/docs.spec.luau", home)
            finally:
                open(arch_path, "w").write(arch)
            fails = [l for l in out.splitlines() if l.startswith("FAIL")]
            if fails and "could not load" not in out:
                killed += 1
                print(f"{mid} ({what}): killed by docs :: {fails[0].split(' :: ', 1)[-1]}")
            else:
                bad += 1
                print(f"{mid} ({what}): SURVIVED")
        mutants += [(d[0], "docs", "", "", "docs") for d in DOCS]
        print(f"{killed} of {len(mutants)} mutants killed")
        print("E2 PASS" if bad == 0 else f"E2 FAIL {bad}")
        return 0 if bad == 0 else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


sys.exit(main())
