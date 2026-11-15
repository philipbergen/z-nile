#!/usr/bin/env python3
"""c0316, E3: apply every document text of the design to a tree (a scratch clone, never the real checkout).

Usage: apply-docs.py <tree root>   (statement.md is read from this script's issue folder)
The executor may run it on the raft's worktree as the starting point of Implementation step 5: the Design and the
docs spec are the contract, this script is not.
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).resolve()
here = pathlib.Path(__file__).resolve().parent.parent


def edit(rel, fn):
    p = root / rel
    old = p.read_text()
    new = fn(old)
    assert new != old, f"{rel}: nothing changed"
    p.write_text(new)


def once(text, a, b):
    assert text.count(a) == 1, (a[:60], text.count(a))
    return text.replace(a, b)


# 1. README: the Goals section, word for word from statement.md, each paragraph and list item on one line
st = (here / "statement.md").read_text()
a = st.index("**z-nile's goals, in order.")
m = st.index("**Measure.**")
end = st.find("\n\n", m)
block = st[a:] if end == -1 else st[a:end]
out = []
for para in block.split("\n\n"):
    cur = []
    for line in para.split("\n"):
        if re.match(r"^(\d+\. |- )", line) and cur:
            out.append(" ".join(cur))
            cur = []
        cur.append(line.strip() if cur else line.rstrip())
    out.append(" ".join(cur))
    out.append("")
goals = "\n".join(out).rstrip("\n")
after = ("The tracker sees an escape as a review finding marked with an earlier stage, a redesign after approval, a "
         "stop of a started raft, or an issue that reworks a merged one (zz-rules, Items); a recorded question is "
         "c0321's.")
edit("z-nile/README.md", lambda t: once(t, "\n## How it should work\n",
                                        f"\n## Goals\n{goals}\n\n{after}\n\n## How it should work\n"))

# 2. AGENTS.md: the last sentence of the Non-negotiable paragraph
AG = (" What the system is for, in order, and what an escape is: `z-nile/README.md`, Goals; an agent never skips or "
      "shortens a check a design or a skill requires, only the human does.")


def agents(t):
    lines = t.split("\n")
    k = [i for i, l in enumerate(lines) if l.startswith("**Non-negotiable:**")]
    assert len(k) == 1
    lines[k[0]] += AG
    return "\n".join(lines)


edit("AGENTS.md", agents)

# 3. the Lessons section of every skill: one sentence in front of its second paragraph
LS = ("An escape (z-nile/README.md, Goals: a mistake found at a later stage than the one that made it) always leaves a "
      "lesson or a stated `one-off`, and work with an unharvested escape does not land. ")
n = 0
for skill in sorted(root.glob("*/skills/*/SKILL.md")):
    if skill.relative_to(root).parts[0].startswith(".") or skill.parent.is_symlink():
        continue  # .claude/skills/<name> links to the real folder: edit each skill once
    t = skill.read_text()
    if "\n## Lessons\n" not in t:
        continue
    skill.write_text(once(t, "\nA new lesson (from a review finding", "\n" + LS + "A new lesson (from a review finding"))
    n += 1
assert n >= 11, n

# 4. zz-rules: the escape entry in Items, and the lessons row
ZR = (" An escape the tracker sees outside a review (z-nile/README.md, Goals) has its own entry: `- escape redesign "
      "<n> (<stage>): <lesson ids>` for approval `<n>` of the item (2 or more), `- escape stop <n> (<stage>): …` in a "
      "raft's ledger for its stop `<n>` after it started, and `- escape rework 1 (<stage>): …` in an item with "
      "`reworks:`; `<stage>` is `idea`, `design` or `implementation`, the stage whose work held the mistake, and the "
      "target may be `one-off: <reason>`. A review finding names its stage in the review (`Stage:`), and one that "
      "names an earlier stage than its review's is an escape. `./zn status <id> prepared`, `./zn ready` (a stop) and "
      "`./zn done` refuse while one has no entry.")
ROW = "; `--uncovered` also lists an escape with no entry, and an unmarked finding"


def rules(t):
    t = once(t, "A note covers no finding.", "A note covers no finding." + ZR)
    lines = t.split("\n")
    k = [i for i, l in enumerate(lines) if l.startswith("| lessons | `./zn lessons")]
    assert len(k) == 1 and lines[k[0]].endswith(" |")
    lines[k[0]] = lines[k[0]][:-2] + ROW + " |"
    return "\n".join(lines)


edit("z-nile/skills/zz-rules/SKILL.md", rules)

# 5. zz-review: the Stage line, item 10 of design mode, a last item of final mode
STAGE = ("Stage: <idea | design | implementation: the stage whose work holds the mistake; an earlier stage than this "
         "review's is an escape>\n")
I10 = (" Challenge every `one-off` in the item's `harvest.md` whose reason does not hold, and every escape entry "
       "(`- escape …`) whose stage or lesson does not fit what happened. Raise a high finding when the documents, the "
       "Verification log or the pull request show a check a design or a skill requires was skipped or shortened and "
       "no ruling of the user is quoted for it: only the human shortens a check (z-nile/README.md, Goals).")
F4 = "4. **Escapes**: design mode's item 10, on the raft's and its members' `harvest.md`.\n"


def review(t):
    t = once(t, "\nLesson: <skill>/<slug> (only when", "\n" + STAGE + "Lesson: <skill>/<slug> (only when")
    lines = t.split("\n")
    k = [i for i, l in enumerate(lines) if l.startswith("10. **Lessons**: Search with")]
    assert len(k) == 1
    lines[k[0]] += I10
    f = lines.index("## Final mode (the finished stack)")
    j = [i for i in range(f, len(lines)) if lines[i].startswith("3. **Judge substance**")]
    assert len(j) == 1
    e = j[0] + 1
    while lines[e].startswith("   "):
        e += 1
    lines.insert(e, F4.rstrip("\n"))
    return "\n".join(lines)


edit("z-nile/skills/zz-review/SKILL.md", review)

# 6. zz-stats: the escapes in the report's list, and the 20% target as history
def stats(t):
    t = once(t, "The target is **under 20%** on all three", "The 20% target is history (z-nile/README.md, Goals)")
    lines = t.split("\n")
    k = [i for i, l in enumerate(lines) if "**size estimates**" in l]
    assert len(k) == 1
    lines[k[0]] += (" It also prints **escapes** (made in which stage, found at which; the target is none after a "
                    "merge).")
    return "\n".join(lines)


edit("z-nile/skills/zz-stats/SKILL.md", stats)

# 7. z-ticket step 3 and the issue template
edit("z-nile/skills/z-ticket/SKILL.md", lambda t: once(
    t, "`depends_on` (IDs) if you already know them.",
    "`depends_on` (IDs) if you already know them, and `reworks: <id>` when the issue corrects something already "
    "merged (any type: a defect of a game, a chore that fixes the tooling)."))
edit("z-nile/templates/issue/doc.md", lambda t: once(t, "\ndepends_on: []\n", "\ndepends_on: []\nreworks: \n"))
print(f"applied: README, AGENTS.md, {n} Lessons sections, zz-rules, zz-review, zz-stats, z-ticket, the template")
