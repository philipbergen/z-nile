--!strict
-- c0286 AC3: the skills say what c0286's Design says. z-raft's policy keeps tied issues together (the tie, the wait and
-- its skip, one raft whatever the size or surface, the fold into the raft that holds the rest, the ties one raft can't
-- hold, a tied raft taking nothing else) and leaves the tie to the caller with arguments; the over-cap rule yields to a
-- tie; zz-rules' raft-plan row names the tie; z-design says when to write `tied:` and whom it names; raftplan's header
-- states the rule. Reads the real tree, plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local SKILLS = "z-nile/skills"
-- runs from its project's home, z-nile/: every path this spec reads is the repository's, from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
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

return t.spec("c0286 the docs keep tied issues together", function(it)
	it("z-raft's policy keeps a tie together, and arguments override it", function()
		local s = read(`{SKILLS}/z-raft/SKILL.md`)
		local w = "z-raft"
		at(
			s,
			"an issue estimated over that is a raft by itself and is never split, unless it is tied (below);",
			w
		)
		absent(s, "an issue estimated over that is a raft by itself and is never split;", w)
		at(s, "  - issues tied together are one raft: an issue's `tied: [<ids>]`", w)
		at(
			s,
			"ties it to each issue it names, both ways, and a tie is every issue those lines connect, whatever its state",
			w
		)
		at(
			s,
			"While any member is not prepared, the plan prints `skip <id>: tied to …` for each prepared one",
			w
		)
		at(s, "once every member is prepared they are one raft, whatever their size or surface", w)
		at(s, "or are folded into the one open raft that already holds some of them", w)
		at(
			s,
			"A tie one raft can't hold (two types or projects, a solo member, members in two rafts or in a raft that is not open) is skipped and named, for z-raft with arguments to decide",
			w
		)
		at(s, "a raft that holds a tied issue takes no other issue from the plan", w)
		-- review 001 F4: a raft being rafted is waited for, and a dispatched member's way through
		at(s, "a tie some of which a raft being rafted holds waits until that rafting lands", w)
		at(
			s,
			"Under `./zn dispatch`, each member prepared before the last stops at its `raft-plan` step on that skip, and the last member's own `raft-plan` step rafts the whole tie; retry a stopped member (`./zn dispatch retry <id>`) only once that rafting PR has merged",
			w
		)
		at(s, "overriding the fold and surface rules, the cap and the ties (`tied:`)", w)
		absent(s, "overriding the fold and surface rules and the cap.", w)
	end)

	it("zz-rules' raft-plan row names the tie", function()
		local s = read(`{SKILLS}/zz-rules/SKILL.md`)
		local w = "zz-rules"
		at(
			s,
			"`skip <id>: <why>` for an issue it can't place (no `size:`, or tied to an issue that is not prepared)",
			w
		)
		-- review 001 F2: an unreadable `tied:` is named on any backlog issue
		at(s, "for any backlog issue whose `tied:` it can't read, prepared or not", w)
		at(s, "features by shared surface, the size cap, solo issues alone, tied issues together)", w)
	end)

	it("z-design says when to write tied: and whom it names", function()
		local s = read(`{SKILLS}/z-design/SKILL.md`)
		local w = "z-design"
		at(s, "and an issue over it is a raft by itself, never split, unless it is tied.", w)
		at(
			s,
			"`tied: [<ids>]`, as the line after `id:`, when a recorded user decision ties the issue to others in one raft",
			w
		)
		at(
			s,
			"name every other issue of the tie, prepared or not, so whichever is prepared first carries it",
			w
		)
		at(s, "z-raft's plan rafts none of them until every one is prepared, then all of them as one raft", w)
	end)

	it("raftplan's header states the rule", function()
		local s = read("z-nile/engine/raftplan.luau")
		at(
			s,
			"c0286: issues tied by `tied:` (a recorded user decision: one raft) are never rafted apart",
			"raftplan.luau"
		)
	end)
end)
