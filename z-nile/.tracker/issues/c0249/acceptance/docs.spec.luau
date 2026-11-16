--!strict
-- c0249 AC8: the words say what the code does. The README's Order section says every issue and raft can carry a rank,
-- unset being valid (the older "gets a rank" line is gone), what claimable means (a worker carries a raft and may draft a
-- design, a person approves it), that z-ticket, z-design and z-raft leave the rank unset, and names `./zn rank`,
-- `./zn next` and the board; the roadmap row says it exists. zz-rules names both commands (the main checkout may run
-- `rank`, `next` only reads) and the rank rule; the three skills say they write no rank; the templates write none; the
-- usage text lists both commands.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function section(text: string, from: string, to: string): string
	return string.match(text, from .. ".-" .. to) or ""
end

return t.spec("c0249 the documents say what the rank does", function(it)
	it(
		"AC8: the README's Order section says unset is valid, what claimable means and who sets a rank",
		function()
			local readme = read("z-nile/README.md")
			local order = section(readme, "### Order", "\n### ")
			t.expect(order ~= "").toBe(true)
			for _, phrase in
				{
					"Every issue and raft can carry a `rank:`",
					"unset is a valid rank",
					"An unset `rank:` is the lowest rank, and equal or unset ranks fall back to the ticket number",
					"whose status is claimable: a worker carries a raft to merge, rafts the approved issues that are in no raft, and may draft the design of an issue, but a person approves it",
					"`./zn next` prints it",
					"z-ticket, z-design and z-raft leave the rank unset (unset by default)",
					"`./zn rank <id> top|last|before <id>|after <id>|<n>|unset`",
					"dragging a card in the board app",
					"A rank given to a raft is the raft's own; an unset one takes the best rank a person set on one of its members (a rank a move wrote on an item, `rank: 30 auto`, does not count)",
					"`./zn list` shows every blocked item first, then lost work, then the rafts and the issues in the stack's order",
					"with lost work first inside each band",
					"(lost work, else a claimable raft, else an approved issue to raft, else an issue to draft)",
					"Lost work comes first",
					"*exists* (c0265)",
				}
			do
				if not has(order, phrase) then
					error(`the README's Order section lacks: {phrase}`, 0)
				end
			end
			-- the older sentences are gone
			t.expect(has(order, "every issue and raft gets a `rank:`")).toBe(false)
			t.expect(has(order, "Tickets have no order today")).toBe(false)
			t.expect(has(order, "z-ticket and z-design append by default")).toBe(false)
			t.expect(has(order, "z-raft asks for a raft's rank")).toBe(false)
			t.expect(
				string.find(
					readme,
					"| `rank`, `./zn rank`, `./zn next`, lost first | c0249 | exists |",
					1,
					true
				) ~= nil
			).toBe(true)
		end
	)

	it("AC8: zz-rules lists both commands where they may run and states the rank rule", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		local main = string.match(
			rules,
			"The complete list of commands that may run there:.-\n   The tracker enforces"
		) or ""
		t.expect(has(main, "`./zn rank <id> …` (c0249)")).toBe(true)
		t.expect(has(main, "fast-forwards the main checkout, as `ready` and `stop` do")).toBe(true)
		t.expect(has(main, "`lost`, `next`, `metrics`")).toBe(true)
		local rank = string.match(rules, "%- %*%*Rank%*%* %(c0249%).-\n%- %*%*") or ""
		for _, phrase in
			{
				"the lowest first, an unset rank (no line, or an empty one) last",
				"A raft's own rank overrides its members'; an unset one takes the best rank a person set on a member",
				"z-ticket, z-design and z-raft write no rank",
				"`./zn next` prints lost work first, then the claimable raft with the best rank",
				"then the best-ranked approved issue that is in no raft",
				"`depends_on` that are not done and a `blocked` status skip an item without changing its rank",
				"appends a `ranked` row to each changed item's `provenance.md`",
				"`./zn list` shows every blocked item first, then lost work",
				"rejects a `rank:` that is not a whole number from 1 to 999999, or is written twice",
			}
		do
			if not has(rank, phrase) then
				error(`zz-rules' Rank bullet lacks: {phrase}`, 0)
			end
		end
		t.expect(has(rules, "or its `rank:` line (what `rank` publishes, for a backlog item only)"))
			.toBe(true)
		t.expect(has(rules, "`./zn rank <id> top|last|before <id>|after <id>|<n>|unset`, `./zn next`"))
			.toBe(true)
	end)

	it("AC8: z-ticket, z-design and z-raft say they write no rank, and the templates write none", function()
		t.expect(has(read("z-nile/skills/z-ticket/SKILL.md"), "Leave `rank:` out")).toBe(true)
		t.expect(has(read("z-nile/skills/z-design/SKILL.md"), "z-design writes no rank")).toBe(true)
		t.expect(has(read("z-nile/skills/z-raft/SKILL.md"), "z-raft does not ask for a rank and writes none"))
			.toBe(true)
		t.expect(has(read("z-nile/skills/z-work/SKILL.md"), "Rank orders the rafts (c0249")).toBe(true)
		for _, template in { "z-nile/templates/issue/doc.md", "z-nile/templates/raft/doc.md" } do
			t.expect(string.match(read(template), "\nrank:") == nil).toBe(true)
		end
	end)

	it("AC8: the usage text lists rank and next", function()
		local main = read("z-nile/engine/main.luau")
		t.expect(has(main, "\n  rank <id> top|last|before <id>|after <id>|<n>|unset\n")).toBe(true)
		t.expect(has(main, "\n  next                                          print the next item to take"))
			.toBe(true)
	end)
	it("AC8: the agents file names rank among the commands that move the main checkout", function()
		local agents = read("AGENTS.md")
		t.expect(
			has(
				agents,
				"(`ready`, `stop`, `rank`, `sync`, and the board refresh after every publish or `land`)"
			)
		).toBe(true)
	end)
end)
