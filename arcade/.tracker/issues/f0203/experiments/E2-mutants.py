# E2 (f0203 prep): the mutation check. Each mutant is one text replacement in the prep prototype
# (arcade/src/shared/Logic/<F>/init.luau, never committed); the named spec must fail on an assertion.
# Run from arcade/: python3 -I .tracker/issues/f0203/experiments/E2-mutants.py
import subprocess, sys
A = ".tracker/issues/f0203/acceptance/"
M = [
 # id, feature, old, new, spec
 ("R1","Rng","multiplier = 48271, mix = 1","multiplier = 16807, mix = 1","rng"),
 ("R2","Rng","g.state = (g.state * g.multiplier) % MODULUS\n\treturn g.state % n + 1","local o = g.state\n\tg.state = (g.state * g.multiplier) % MODULUS\n\treturn o % n + 1","rng"),
 ("R3","Rng","s = s % (MODULUS - 1)\n","","rng"),
 ("R4","Rng","then math.floor(seed)\n\t\telse 0","then math.floor(seed)\n\t\telse seed","rng"),
 ("R5","Rng","if not whole(n) or n < 1 then","if false then","rng"),
 ("R6","Rng","return (g.state - 1) / (MODULUS - 1)","return g.state / MODULUS","rng"),
 ("R7","Rng","return Rng.int(g, n)","return Rng.int(table.clone(g), n)","rng"),
 ("R8","Rng","st.multiplier >= MAX_MULTIPLIER","st.multiplier >= MODULUS","rng"),
 ("R9","Rng","then math.floor(seed)\n","then seed\n","rng"),
 ("P1","Pad","if r >= t.on then\n\t\t\tlocal now = sector","if r > t.on then\n\t\t\tlocal now = sector","pad"),
 ("P2","Pad","\tif r < t.off then\n\t\treturn { held = nil }, nil\n\tend\n\tif r >= t.on and off(","\tif r < t.on then\n\t\treturn { held = nil }, nil\n\tend\n\tif r >= t.on and off(","pad"),
 ("P3","Pad","> 45 + t.margin + 1e-9","> 45 + 1e-9","pad"),
 ("P4","Pad","if math.abs(y) >= math.abs(x) then","if math.abs(y) > math.abs(x) then","pad"),
 ("P5","Pad","local r = math.abs(x)\n","local r = math.sqrt(x * x + y * y)\n","pad"),
 ("P5b","Pad","if r >= t.on and now ~= s.held then","if r >= t.on and now ~= s.held and false then","pad"),
 ("P6","Pad","local a = scaled * scaled","local a = scaled","pad"),
 ("P7","Pad","local dyaw = -a * (x / r)","local dyaw = a * (x / r)","pad"),
 ("P8","Pad","return dyaw, if t.invert then -dpitch else dpitch","return if t.invert then -dyaw else dyaw, if t.invert then -dpitch else dpitch","pad"),
 ("P9","Pad","magnitude >= t.off then","magnitude >= t.on then","pad"),
 ("P10","Pad","function Pad.steer(s: Steer, x: number, y: number, tuning: Tuning?): (Steer, Dir?)\n\tlocal t = tuning or Pad.DEFAULT","function Pad.steer(s: Steer, x: number, y: number, tuning: Tuning?): (Steer, Dir?)\n\tlocal t = if tuning and tuning.axes == \"horizontal\" then tuning else Pad.DEFAULT","pad"),
 ("P11","Pad","t.off > 0 and t.off < t.on and t.on <= 1","t.off > 0","pad"),
 ("P12","Pad","or not finite(dt) or dt <= 0 then","then","pad"),
 ("P13","Pad","if not finite(x) or not finite(y) then\n\t\treturn { held = nil }, nil","if false then\n\t\treturn { held = nil }, nil","pad"),
 ("P14","Pad","return n ~= nil and n >= 1 and n <= 8","return n ~= nil","pad"),
 ("T1","Touch","table.insert(effects, { kind = \"release\", name = finger.button })","","touch"),
 ("T2","Touch","for _, b in ctx.buttons do\n\t\tif Touch.inside","for i = #ctx.buttons, 1, -1 do\n\t\tlocal b = ctx.buttons[i]\n\t\tif Touch.inside","touch"),
 ("T3","Touch","x < r.x + r.w and y < r.y + r.h","x <= r.x + r.w and y <= r.y + r.h","touch"),
 ("T4","Touch","Touch.swipe(event.x - finger.x0, event.y - finger.y0)","Touch.swipe(event.x - finger.x, event.y - finger.y)","touch"),
 ("T5","Touch","< Touch.MIN_SWIPE then","<= Touch.MIN_SWIPE then","touch"),
 ("T6","Touch","math.rad(Touch.AXIS_DEGREES) + 1e-9","math.rad(45) + 1e-9","touch"),
 ("T7","Touch","taken = taken or same(f, button, side)","taken = taken","touch"),
 ("T8","Touch","return nil, side, if side == \"left\" then ctx.left else ctx.right","return nil, side, if side == \"left\" then \"swipe\" else \"look\"","touch"),
 ("T9","Touch","if bad and event.phase ~= \"end\" then","if bad then","touch"),
 ("T10","Touch","\ttable.sort(ids)\n","\ttable.sort(ids, function(a, b) return a > b end)\n","touch"),
 ("T11","Touch","local fingers: { [number]: Finger } = table.clone(state.fingers)","local fingers: { [number]: Finger } = state.fingers","touch"),
 ("T12","Touch","x < ctx.width / 2 then \"left\" else \"right\"\n\treturn nil","x <= ctx.width / 2 then \"left\" else \"right\"\n\treturn nil","touch"),
 ("T13","Touch","if button ~= nil or use ~= \"none\" then","if true then","touch"),
 ("T14","Touch","if dy > 0 then \"down\" else \"up\"","if dy < 0 then \"down\" else \"up\"","touch"),
 ("T15","Touch","if finger.button == nil and finger.use == \"look\" then","if finger.button == nil then","touch"),
 ("L1","Look","if r == -PI then\n\t\treturn PI\n\tend","","look"),
 ("L2","Look","local diff = Look.wrap(target - current)","local diff = target - current","look"),
 ("L3","Look","if current == nil or not finite(current) then\n\t\treturn Look.wrap(target)","if current == nil or not finite(current) then\n\t\treturn 0","look"),
 ("L4","Look","return (PI / 2) / t.turnSeconds","return (PI / 2) / 0.12","look"),
 ("L5","Look","yaw = Look.wrap(l.yaw - dx * k)","yaw = Look.wrap(l.yaw + dx * k)","look"),
 ("L6","Look","return math.clamp(p, -t.maxPitch, t.maxPitch)","return p","look"),
 ("L7","Look","if not finite(dx) or not finite(dy) then","if false then","look"),
 ("L8","Look","return side * 1.5","return -side * 1.5","look"),
 ("L9","Look","return { look = toward(prev.look, {","return { look = toward(look, {","look"),
 ("L10","Look","spring = not (back.yaw == 0 and back.pitch == 0)","spring = true","look"),
 ("L11","Look","if look.yaw ~= prev.look.yaw or look.pitch ~= prev.look.pitch then","if false then","look"),
 ("L12","Look","return math.clamp(a, 0, 1)\nend","return a\nend","look"),
 ("L13","Look","return Look.wrap(from + Look.wrap(to - from) * a)","return Look.wrap(from + (to - from) * a)","look"),
 ("L14","Look","t.maxPitch > 0 and t.maxPitch <= PI / 2","t.maxPitch > 0","look"),
 ("L15","Look","return Look.rate(t) * (if finite(dt) and dt > 0 then dt else 0)","return Look.rate(t) * dt","look"),
 ("L16","Look","local ahead = (if a.up then 1 else 0) - (if a.down then 1 else 0)","local ahead = (if a.up then 1 else 0)","look"),
 ("G1","Pad","local Pad = {}\n","local Pad = {}\nPad.BUTTONS = { ButtonA = \"Jump\" }\n","games"),
]
bad = 0
for mid, feat, old, new, spec in M:
    path = f"src/shared/Logic/{feat}/init.luau"
    src = open(path).read()
    if src.count(old) != 1:
        print(f"{mid}: NOT APPLIED (found {src.count(old)})"); bad += 1; continue
    open(path, "w").write(src.replace(old, new))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", A + spec + ".spec.luau"], capture_output=True, text=True, timeout=120)
    finally:
        open(path, "w").write(src)
    out = r.stdout + r.stderr
    fails = [l for l in out.splitlines() if l.startswith("FAIL")]
    loaderr = "could not load" in out or "error requiring" in out
    if fails and not loaderr:
        print(f"{mid}: killed by {spec} :: {fails[0].split(' :: ',1)[-1]}")
    else:
        print(f"{mid}: SURVIVED ({'load error' if loaderr else 'no failure'})"); bad += 1
print("E2 PASS" if bad == 0 else f"E2 FAIL {bad}")
