--!strict
-- readycheck.reason is every check `./zn ready` makes before the carried move. The grouping record
-- is readycheck.record, which the carried move judges on the tree being published.
local contract = require("@znile/engine/contract")
local raftplan = require("@znile/engine/raftplan")
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")

local DOC = table.concat({
	"---",
	"id: c0001",
	"design: ready",
	"---",
	"",
	"# c0001",
	"",
	"## Problem",
	"P",
	"",
	"## Solution",
	"S",
	"",
	"## Design",
	"D",
	"",
	"## Acceptance criteria",
	"A",
	"",
	"## Test plan",
	"T",
	"",
}, "\n")

local CHECK = 'check "AC1: holds" true\n'

local function member(approval: string?): readycheck.Member
	return {
		id = "c0001",
		design = "ready",
		doc = DOC,
		deps = {},
		files = { ["c0001.md"] = DOC, ["check.sh"] = CHECK, ["approval.md"] = approval or "" },
		specs = {},
		approval = approval,
		approvalFile = "z-nile/.tracker/issues/c0001/approval.md",
	}
end

local function raft(over: { [string]: any }): readycheck.Raft
	local r: readycheck.Raft = {
		id = "R0001",
		where = "backlog",
		status = "prepared",
		dir = "z-nile/.tracker/rafts/R0001",
		design = "ready",
		doc = "---\ndesign: ready\n---\n",
		grouped = nil,
		questions = false,
		listed = { "c0001" },
		members = { member(nil) },
		files = { ["check.sh"] = CHECK },
		loaded = true,
	}
	for k, v in over do
		(r :: any)[k] = v
	end
	return r
end

return t.spec("ready would accept it", function(it)
	it("refuses questions, a held raft, and a missing approval", function()
		local asked = raft({ questions = true })
		local why = readycheck.reason(asked)
		t.expect(string.find(why or "", "questions.md", 1, true) ~= nil).toBe(true)
		local held = raft({ where = "active", status = "active" })
		t.expect(string.find(readycheck.reason(held) or "", "only a prepared raft", 1, true) ~= nil)
			.toBe(true)
		-- f0399: under ./zn dispatch every member needs an approval; outside it, done asks, not ready
		local bare = readycheck.reason(raft({ requireApproval = true }))
		t.expect(string.find(bare or "", "./zn approve c0001 --publish", 1, true) ~= nil).toBe(true)
		t.expect((readycheck.reason(raft({})))).toBe(nil)
	end)

	it(
		"outside dispatch an approved member may gain a guess, and no other part may change (f0399)",
		function()
			local built = contract.build(DOC, CHECK, {}) :: contract.Parts
			local text = contract.render({
				{
					when = "2026-11-13T00:00:00Z",
					who = "Ada",
					hash = contract.hash(built),
					parts = contract.partHashes(built),
				},
			})
			local guessed = member(text)
			guessed.files["guesses.md"] =
				"# guesses\n- G1 (design, 2026-11-16): Open. Chose: Two. Why: Because.\n"
			t.expect((readycheck.reason(raft({ members = { guessed } })))).toBe(nil)
			local strict = readycheck.reason(raft({ members = { guessed }, requireApproval = true }))
			t.expect(string.find(strict or "", "contract changed since approval: guesses", 1, true) ~= nil)
				.toBe(true)
			local edited = member(text)
			edited.doc = (string.gsub(DOC, "\nD\n", "\nchanged\n"))
			local why = readycheck.reason(raft({ members = { edited } }))
			t.expect(string.find(why or "", "contract changed since approval", 1, true) ~= nil).toBe(true)
			local broken = member(nil)
			broken.files["guesses.md"] = "# guesses\n- G2 (design, 2026-11-16): Skips. Chose: x. Why: y.\n"
			t.expect(
				string.find(readycheck.reason(raft({ members = { broken } })) or "", "guesses.md", 1, true)
					~= nil
			).toBe(true)
		end
	)

	it(
		"a Guessed line must name a recorded guess, and --on takes the base raft's members as done (f0399)",
		function()
			local open =
				"\n## Open to the human\n- F1: the finding. Answer: none. Decision: which?\n  Guessed (agent, 2026-11-16): G1\n"
			local problem = readycheck.guessedProblem(
				"c0001",
				DOC .. open,
				"c0001",
				function(_id: string): string?
					return nil
				end
			)
			t.expect(problem)
				.toBe("c0001: F1's Guessed line names c0001 G1, which is not in c0001's guesses.md")
			local fine = readycheck.guessedProblem(
				"c0001",
				DOC .. open,
				"c0001",
				function(_id: string): string?
					return "# guesses\n- G1 (design, 2026-11-16): Open. Chose: Two. Why: Because.\n"
				end
			)
			t.expect(fine).toBe(nil)
			local waiting = member(nil)
			waiting.deps = { { id = "c0099", state = "active" } }
			t.expect(
				string.find(
					readycheck.reason(raft({ members = { waiting } })) or "",
					"must be done first",
					1,
					true
				) ~= nil
			).toBe(true)
			t.expect((readycheck.reason(raft({ members = { waiting }, onMembers = { "c0099" } })))).toBe(nil)
		end
	)

	it("accepts a member whose approval still holds", function()
		local parts = contract.build(DOC, CHECK, {})
		t.expect(parts ~= nil).toBe(true)
		local built = parts :: contract.Parts
		local text = contract.render({
			{
				when = "2026-11-13T00:00:00Z",
				who = "Ada",
				hash = contract.hash(built),
				parts = contract.partHashes(built),
			},
		})
		local why = readycheck.reason(raft({ members = { member(text) } }))
		t.expect(why).toBe(nil)
	end)

	it("proceeds exactly when reason and the publish-tree record are both nil", function()
		local function issueDoc(id: string): string
			return (string.gsub(DOC, "c0001", id))
		end
		local function approvalOf(doc: string): string
			local parts = contract.build(doc, CHECK, {})
			local built = parts :: contract.Parts
			return contract.render({
				{
					when = "2026-11-13T00:00:00Z",
					who = "Ada",
					hash = contract.hash(built),
					parts = contract.partHashes(built),
				},
			})
		end
		local function one(
			id: string,
			files: { [string]: string },
			deps: { readycheck.Dep }
		): readycheck.Member
			local doc = files[`{id}.md`]
			local approved = approvalOf(doc)
			files["approval.md"] = approved
			return {
				id = id,
				design = "ready",
				doc = doc,
				deps = deps,
				files = files,
				specs = {},
				approval = approved,
				approvalFile = `pickman/.tracker/issues/{id}/approval.md`,
			}
		end
		local function designOf(id: string, harvest: string): { [string]: string }
			return { [`{id}.md`] = issueDoc(id), ["check.sh"] = CHECK, ["harvest.md"] = harvest }
		end
		local function groupedOf(members: { readycheck.Member }): string
			local map: { [string]: string } = {}
			for _, m in members do
				map[m.id] = raftplan.recordHash(m.id, m.files)
			end
			return raftplan.renderGrouped(map)
		end
		local function whole(
			members: { readycheck.Member },
			grouped: string?,
			review: string?,
			over: { [string]: any }
		): readycheck.Raft
			local ids: { string } = {}
			for _, m in members do
				table.insert(ids, m.id)
			end
			local files: { [string]: string } = { ["check.sh"] = CHECK }
			if review and grouped then
				files["design-review-001.md"] = `Grouped: {grouped}\n`
			end
			local r = raft({
				listed = ids,
				members = members,
				grouped = grouped,
				files = files,
			})
			for k, v in over do
				(r :: any)[k] = v
			end
			return r
		end
		-- Ready proceeds only when the pre-move check is nil and the publish validator's record is nil.
		-- The record is not inside reason: it reads the tree being published, not a disk walk.
		local function recordOf(r: readycheck.Raft): string?
			return readycheck.record(r.id, r.grouped, r.members, r.files)
		end
		local function proceeds(r: readycheck.Raft): boolean
			return readycheck.reason(r) == nil and recordOf(r) == nil
		end
		local keep = "kept\n"
		local a = one("c0001", designOf("c0001", keep), {})
		local b = one("c0002", designOf("c0002", keep), {})
		local folded = whole({ a, b }, groupedOf({ a, b }), "review", {})
		local staleFiles = designOf("c0001", keep)
		staleFiles["acceptance/.DS_Store"] = "finder"
		local walked = one("c0001", staleFiles, {})
		local walkedMate = one("c0002", designOf("c0002", keep), {})
		local published = { a, walkedMate }
		local disk = whole({ walked, walkedMate }, groupedOf(published), "review", {})
		local redesignedFiles = designOf("c0002", keep)
		local redesignedMate = one("c0002", redesignedFiles, {})
		local before = groupedOf({ a, redesignedMate })
		redesignedFiles["harvest.md"] = "rewritten\n"
		local redesigned = whole({ a, one("c0002", redesignedFiles, {}) }, before, "review", {})
		local changedDoc = issueDoc("c0001") .. "\n## Design\nchanged\n"
		local changedFiles = { ["c0001.md"] = issueDoc("c0001"), ["check.sh"] = CHECK, ["harvest.md"] = keep }
		local changed = one("c0001", changedFiles, {})
		changed.doc = changedDoc
		changed.files["c0001.md"] = changedDoc
		local rows: { { string } } = {
			{
				"approved",
				if proceeds(whole({ a }, groupedOf({ a }), nil, {})) then "proceeds" else "refuses",
			},
			{
				"unapproved",
				if proceeds(whole({ member(nil) }, nil, nil, {})) then "proceeds" else "refuses",
			},
			{
				"unapproved under dispatch",
				if proceeds(whole({ member(nil) }, nil, nil, { requireApproval = true }))
					then "proceeds"
					else "refuses",
			},
			{
				"approval changed",
				if proceeds(whole({ changed }, groupedOf({ a }), nil, {})) then "proceeds" else "refuses",
			},
			{ "folded with its review", if proceeds(folded) then "proceeds" else "refuses" },
			{ "member redesigned since grouping", if proceeds(redesigned) then "proceeds" else "refuses" },
			{
				"dependency not done",
				if proceeds(
						whole(
							{ one("c0001", designOf("c0001", keep), { { id = "c0099", state = "backlog" } }) },
							nil,
							nil,
							{}
						)
					)
					then "proceeds"
					else "refuses",
			},
			{
				"questions present",
				if proceeds(whole({ a }, groupedOf({ a }), nil, { questions = true }))
					then "proceeds"
					else "refuses",
			},
			{
				"held",
				if proceeds(whole({ a }, groupedOf({ a }), nil, { where = "active", status = "active" }))
					then "proceeds"
					else "refuses",
			},
			{ "no members", if proceeds(whole({}, nil, nil, {})) then "proceeds" else "refuses" },
		}
		local expect = {
			approved = "proceeds",
			unapproved = "proceeds", -- f0399: done asks for the approval, not ready
			["unapproved under dispatch"] = "refuses",
			["approval changed"] = "refuses",
			["folded with its review"] = "proceeds",
			["member redesigned since grouping"] = "refuses",
			["dependency not done"] = "refuses",
			["questions present"] = "refuses",
			held = "refuses",
			["no members"] = "refuses",
		}
		for _, row in rows do
			t.expect(row[2]).toBe(expect[row[1]])
		end
		t.expect((readycheck.reason(folded))).toBe(nil)
		t.expect(recordOf(folded)).toBe(nil)
		t.expect((readycheck.reason(redesigned))).toBe(nil)
		t.expect(string.find(recordOf(redesigned) or "", "changed on origin/main since", 1, true) ~= nil)
			.toBe(true)
		-- The fold case ready publishes has no ignored file. A disk walk that includes one refuses.
		t.expect(recordOf(disk) ~= nil).toBe(true)
		t.expect(string.find(recordOf(disk) or "", "c0001 (", 1, true) ~= nil).toBe(true)
	end)
end)
