--!strict
-- c0116 AC6: the skills, the README, AGENTS.md and the usage say what c0116's Design says. z-design designs one issue
-- and makes no raft (its reviews, harvest and spend on the issue, `size:` and `solo:` recorded, next step z-raft); the
-- new z-raft skill holds the policy, the lock, the commands, the raft's design and the coherence review; zz-rules,
-- zz-review, zz-stats and z-ready move with it; the README draws z-raft as built. Reads the real tree, plain finds only.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local SKILLS = "z-nile/skills"
local function read(path: string): string
	return fs.readFile(path)
end
local function at(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{where} is missing: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{where} still says: {needle}`, 2)
	end
end

return t.spec("c0116 the docs split rafting out of design", function(it)
	it("z-design designs one issue, claims it alone, keeps its reviews on it, and makes no raft", function()
		local s = read(`{SKILLS}/z-design/SKILL.md`)
		local w = "z-design"
		absent(s, "./zn new raft", w)
		absent(s, "Form the raft", w)
		absent(s, "spend <R-id>", w)
		absent(s, "promote-check <R-id>", w)
		absent(s, "status <R-id> prepared", w)
		at(
			s,
			"z-design designs one issue to `design: ready` and status `prepared`, and does not create a raft",
			w
		)
		at(s, "- **Claim it**: `./zn status <id> preparing` publishes the claim on `origin/main` at once", w)
		at(
			s,
			"z-design makes no raft: it ends at a prepared issue with no raft, and z-raft groups it later.",
			w
		)
		at(s, "It writes `design-review-NNN.md` in the issue's folder.", w)
		at(s, "`./zn spend <id> --phase design-review --time <reviewer minutes>", w)
		at(s, "to `harvest.md` in the issue's folder", w)
		at(s, "`./zn promote-check <id>`", w)
		at(s, "`./zn lessons --uncovered <id>`", w)
		at(s, "- **Size and solo** (frontmatter, for z-raft): `size: <n>`", w)
		at(s, "`solo: true` only when a recorded user decision says the issue lands as its own raft", w)
		at(s, "**then run `./zn status <id> prepared`**", w)
		at(s, "Leave `raft:` empty: z-raft writes it.", w)
		at(s, "`./zn spend <id> --phase prep --time", w)
		at(s, "- **Next step**: `/z-raft` (it groups prepared issues), then `/z-ready <R-id>`.", w)
	end)

	it(
		"z-raft holds the policy, the lock, the commands, the raft's design and the coherence review",
		function()
			local s = read(`{SKILLS}/z-raft/SKILL.md`)
			local w = "z-raft"
			at(s, "---\nname: z-raft\n", w)
			at(s, "An issue's raft is its own `raft:` line.", w)
			at(
				s,
				"The published claim (`preparing-…`) stamps the raft only: a prepared issue is never restamped.",
				w
			)
			at(s, "- **No argument**: run `./zn raft-plan`.", w)
			at(s, "one type per raft and one project per raft", w)
			at(s, "never pulled in, and a `single: true` raft never takes another issue", w)
			at(
				s,
				"defects fold into one open prepared defect raft (the lowest id that still fits), and chores fold the same way",
				w
			)
			at(s, "features group only when they share a surface", w)
			at(s, "an issue with no Touched modules shares nothing", w)
			at(
				s,
				"a raft that would pass about 1,500 changed lines (the sum of its members' `size:`) starts another",
				w
			)
			at(s, "an issue estimated over that is a raft by itself and is never split", w)
			at(s, "a `solo: true` issue is always a raft by itself", w)
			at(s, "an issue with no `size:` is skipped and named", w)
			at(s, "- **With arguments, it does what was asked**", w)
			at(s, "one type, backlog only, one project, and solo issues alone", w)
			for _, cmd in
				{
					"`./zn raft-plan --apply`",
					"`./zn fold <R-id> <ids…>`",
					"`./zn recombine <keeper> <other> [<ids>…]`",
					"`./zn release <R-id>`",
				}
			do
				at(s, cmd, w)
			end
			at(s, "retires the other (deletes its folder in this branch) only when it ends up empty", w)
			at(s, "- **Theme**:", w)
			at(s, "- **Whole-raft design**: the interfaces between the members", w)
			at(s, "- **Order & dependencies**: the members in `depends_on` order, then by id", w)
			at(s, "z-raft sets a raft's `design:`; z-design sets an issue's.", w)
			at(
				s,
				"one short, raft-only coherence review before it is prepared, always for features that share a surface",
				w
			)
			at(s, "zz-review skill in **raft mode**", w)
			at(s, "this skill never edits a member's design", w)
			at(s, "One round: there is no second.", w)
			at(s, "`./zn status <R-id> prepared`", w)
			at(
				s,
				"A conflict on an issue's `raft:` line when you sync means another rafting PR landed first",
				w
			)
		end
	)

	it("zz-rules states the lock, the commands in every list, and who sets design:", function()
		local s = read(`{SKILLS}/zz-rules/SKILL.md`)
		local w = "zz-rules"
		at(
			s,
			"- **Rafting** (z-raft). An issue's raft is its own `raft:` line, edited only in the rafting PR",
			w
		)
		at(
			s,
			"A raft move (`status <R-id> preparing|new`) never restamps a member that is `prepared` on `origin/main`",
			w
		)
		at(
			s,
			"A conflict on `raft:` or `depends_on:` (they are adjacent lines) after a sync means rerun z-raft",
			w
		)
		at(s, "| raft-plan | `./zn raft-plan [--apply]` |", w)
		at(s, "| fold | `./zn fold <R-id> <issue>...` |", w)
		at(s, "| recombine | `./zn recombine <keeper> <other> [<issue>...]` |", w)
		at(s, "| release | `./zn release <R-id> [--force]` |", w)
		at(
			s,
			"`lessons`, `raft-plan` (without `--apply`), `skills --check` and `capture <id>` (they only read)",
			w
		)
		at(s, "`status <id> <to>`, `fold`, `recombine`, `release`, `raft-plan --apply`, `compact`", w)
		at(s, "`./zn release <R-id> [--force]`\n", w)
		at(s, "`z-design` sets an issue's and `z-raft` a raft's", w)
		at(s, "a raftless issue goes to z-raft", w)
		at(s, "z-raft makes every raft", w)
		at(s, "`./zn spend <issue> --phase prep`", w)
		at(s, "`./zn spend <issue> --phase design-review`", w)
		at(s, "from z-design, on the issue; z-raft's coherence review, on the raft", w)
		at(s, "| rafting (z-raft) | `raft-<slug>` |", w)
		absent(s, "made by z-design in its prep worktree", w)
		absent(s, "goes back to z-design", w)
	end)

	it("zz-review, zz-stats, z-ready, the README, AGENTS.md and the usage move with it", function()
		local review = read(`{SKILLS}/zz-review/SKILL.md`)
		at(review, "## Raft mode (from z-raft)", "zz-review")
		at(
			review,
			"- Design mode: `design-review-NNN.md`, in the issue's folder (z-design reviews one issue)",
			"zz-review"
		)
		absent(review, "in the raft's directory (`./zn metrics` counts rounds from there)", "zz-review")
		local stats = read(`{SKILLS}/zz-stats/SKILL.md`)
		at(stats, "**design rounds per issue**", "zz-stats")
		at(stats, "**size estimates**", "zz-stats")
		local ready = read(`{SKILLS}/z-ready/SKILL.md`)
		at(ready, "If the issue has no raft, stop: z-raft makes one", "z-ready")
		absent(ready, "z-design makes one", "z-ready")
		local readme = read("z-nile/README.md")
		at(readme, 'zraft["z-raft"]', "the README")
		absent(readme, "z-raft (c0116, planned)", "the README")
		at(readme, "3. **z-raft**, in `raft-<slug>`", "the README")
		at(read("AGENTS.md"), "| `z-nile/skills/z-raft/SKILL.md` |", "AGENTS.md")
		local main = read("z-nile/engine/main.luau")
		for _, line in
			{
				"  fold <R-id> <issue>...",
				"  recombine <keeper> <other> [<issue>...]",
				"  release <R-id> [--force]",
				"  raft-plan [--apply]",
				"  promote-check <R-id|issue-id>",
			}
		do
			at(main, line, "the usage")
		end
	end)
end)
