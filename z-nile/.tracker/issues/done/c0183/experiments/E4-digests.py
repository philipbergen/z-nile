# c0183 E4: rebuild the nine files Design items 3 and 4 describe from this issue's document, and print each one's
# SHA-256, the digests designs.spec.luau and check.sh pin. Reads only. Usage: python3 E4-digests.py [c0183.md]
import hashlib, pathlib, re, sys
doc = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent.parent / "c0183.md").read_text().split("\n")
G = ("The source of truth for this project's product decisions, from the user's request of 2026-10-31 "
     "(captured in c0183). Every design in this project must agree with it. Changes happen through the user, never "
     "during execution.")
A = ("The shared library's design, from the plan the user approved on 2026-10-31 (captured in c0183). "
     "Every design that uses the library must agree with it; changing it is a design decision, made in z-design.")
MOVED = [("snake/.tracker/game-design.md", "Snake game design", G, None, None),
         ("invaders/.tracker/game-design.md", "Invaders game design", G, None, None),
         ("asteroids/.tracker/game-design.md", "Asteroids game design", G, None, None),
         ("portal/.tracker/game-design.md", "Portal game design", G, None, None),
         ("arcade/.tracker/architecture.md", "Arcade architecture", A, "##### Context", "##### Tracker work")]
def moved(f, title, note, frm, to):
    s = next(i for i, l in enumerate(doc) if l.startswith("#### `" + f + "`"))
    block = []
    for l in doc[s + 1:]:
        if re.match(r"^#### `", l) or re.match(r"^##? ", l) or re.match(r"^### ", l): break
        block.append(l)
    i = 0
    while block[i] == "": i += 1
    while i < len(block) and block[i] != "": i += 1
    body, keep = [], frm is None
    for l in block[i:]:
        if frm and l.startswith(frm): keep = True
        elif to and l.startswith(to): keep = False
        if keep: body.append(re.sub(r"^##### ", "## ", l))
    while body and body[0] == "": body.pop(0)
    while body and body[-1] == "": body.pop()
    return f"# {title}\n\n{note}\n\n" + "\n".join(body) + "\n"
def stub(title):
    return (f"# {title} architecture\n\nNo code yet: c0184 scaffolds this home and c0185 gates code shared across "
            "homes. Shared code comes from the `arcade` library (`arcade/.tracker/architecture.md`). This file grows "
            "with the project's first design.\n")
out = [(m[0], moved(*m)) for m in MOVED]
out += [(f"{n.lower()}/.tracker/architecture.md", stub(n)) for n in ["Portal", "Snake", "Invaders", "Asteroids"]]
for path, text in out:
    print(hashlib.sha256(text.encode()).hexdigest(), path)
