"""headroom.py <worktree>: how many more non-constant top-level locals main.luau takes before `./zn --help` fails to
compile. Restores the file afterwards."""
import subprocess, sys

root = sys.argv[1]
p = f"{root}/z-nile/engine/main.luau"
orig = open(p).read()
try:
    last_ok = 0
    for k in range(1, 30):
        extra = "".join(f"local probe{i} = os.clock()\n" for i in range(1, k + 1))
        open(p, "w").write(orig.replace("local H = {}\n", "local H = {}\n" + extra, 1))
        r = subprocess.run(["./zn", "--help"], cwd=root, capture_output=True, text=True)
        if "Out of local registers" in (r.stdout + r.stderr):
            print(f"headroom: {last_ok} more top-level locals; +{k} fails")
            break
        last_ok = k
    else:
        print(f"headroom: at least {last_ok}")
finally:
    open(p, "w").write(orig)
