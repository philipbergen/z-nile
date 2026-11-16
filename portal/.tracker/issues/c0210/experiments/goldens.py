#!/usr/bin/env python3
# c0210 prep (design review 001 F1): writes the reviewed text of every promoted spec this chore overrides into
# acceptance/override-<n>.txt and prints the digest of every other file in the folders it touches, for
# acceptance/overrides.spec.luau. Both are masked as c0172's narrowed.spec masks them (item ids to ID, CRLF to LF).
# Run from the reviewed prototype's top, which holds the change and c0194 done (or its branch merged):
#   python3 <this file> <the prep's acceptance folder>
# Never run by the executor: the goldens are prep's, and a byte beyond them is an escalation.
import hashlib, os, re, sys

FOLDERS = [
    ("pickman", "c0003"), ("pickman", "c0015"), ("pickman", "c0051"), ("pickman", "c0064"),
    ("z-nile", "c0120"), ("z-nile", "c0172"), ("z-nile", "c0193"), ("z-nile", "c0194"),
]
OVERRIDES = [
    ("pickman", "c0003", "runner.spec.luau"), ("pickman", "c0003", "runner-e2e.spec.luau"),
    ("pickman", "c0015", "deploy-cli.spec.luau"), ("pickman", "c0015", "deploy-e2e.spec.luau"),
    ("pickman", "c0015", "workflow.spec.luau"),
    ("pickman", "c0064", "plan.spec.luau"), ("pickman", "c0064", "deploy.spec.luau"),
    ("pickman", "c0064", "runtime.spec.luau"), ("pickman", "c0064", "docs.spec.luau"),
    ("pickman", "c0064", "workflow.spec.luau"),
    ("z-nile", "c0120", "ci.spec.luau"), ("z-nile", "c0120", "layout.spec.luau"), ("z-nile", "c0120", "docs.spec.luau"),
    ("z-nile", "c0172", "cicd.spec.luau"), ("z-nile", "c0172", "merge.spec.luau"), ("z-nile", "c0172", "narrowed.spec.luau"),
    ("z-nile", "c0194", "callers.spec.luau"),
]


def exact(text):
    text = text.replace("\r\n", "\n")
    return re.sub(r"(?<![A-Za-z0-9_])[fdcR]\d+(?![A-Za-z0-9_])", "ID", text)


def watch(name):
    return name == "watch.txt" or name.endswith(".watch.txt")


out = sys.argv[1]
for old in os.listdir(out):
    if old.startswith("override-") and old.endswith(".txt"):
        os.remove(os.path.join(out, old))
for n, (home, item, name) in enumerate(OVERRIDES, 1):
    text = open(f"{home}/tests/acceptance/{item}/{name}", encoding="utf-8").read()
    open(os.path.join(out, f"override-{n:02d}.txt"), "w", encoding="utf-8").write(exact(text))
    print(f'\t{{ "{home}", "{item}", "{name}", "{n:02d}.txt" }},')
print("-- unchanged")
over = {(h, i, f) for h, i, f in OVERRIDES}
for home, item in FOLDERS:
    for name in sorted(os.listdir(f"{home}/tests/acceptance/{item}")):
        if watch(name) or (home, item, name) in over:
            continue
        text = open(f"{home}/tests/acceptance/{item}/{name}", encoding="utf-8").read()
        print(f'\t{{ "{home}", "{item}", "{name}", "{hashlib.sha256(exact(text).encode()).hexdigest()}" }},')
