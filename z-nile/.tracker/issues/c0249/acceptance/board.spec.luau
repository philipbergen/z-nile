--!strict
-- c0249 AC5: the board shows the stack in order. boardview.bands orders the cards of a column (a blocked band first, then
-- a set rank before an unset one, the lower first, then the ticket number; a raft band is placed by its raft's rank, the
-- raftless band by its best card), and board.collect gives every issue and raft its rank and puts the bands in that
-- order, over a fixture checkout. Fixture under .cache/c0249-board.
local board = require("@znile/engine/board")
local boardview = require("@znile/engine/boardview")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local repo = `{here}/.cache/c0249-board`
local G = "game/.tracker"

local function write(path: string, text: string)
	local full = `{repo}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function item(path: string, front: { string })
	local id = string.match(path, "([^/]+)$") :: string
	write(
		`{path}/{id}.md`,
		"---\nid: " .. id .. "\n" .. table.concat(front, "\n") .. "\n---\n\n# " .. id .. "\n"
	)
end
local function show(bands: { boardview.Band }): string
	local out: { string } = {}
	for _, b in bands do
		table.insert(out, `{b.raft or "-"}[{table.concat(b.ids, ",")}]`)
	end
	return table.concat(out, " ")
end
local function card(
	id: string,
	raft: string?,
	rank: number?,
	raftRank: number?,
	blocked: boolean?
): boardview.Card
	return { id = id, raft = raft, rank = rank, raftRank = raftRank, blocked = blocked }
end

return t.spec("c0249 the board shows the stack in order", function(it)
	it(
		"AC5: a column's cards are ordered by rank, then ticket number, inside the bands and among them",
		function()
			-- no ranks: the order the board had, a raft band per raft by number, the raftless cards last, ids by number
			t.expect(show(boardview.bands({
				card("c0300"),
				card("f0020", "R0002"),
				card("c0010", "R0002"),
				card("d0100", "R0001"),
				card("c0200"),
			}))).toBe("R0001[d0100] R0002[c0010,f0020] -[c0200,c0300]")
			-- a set rank before an unset one inside a band: c0300 (3) first although its number is the highest
			t.expect(show(boardview.bands({
				card("c0010", "R0001"),
				card("c0300", "R0001", 3, 3),
				card("c0200", "R0001", 3, 3),
			}))).toBe("R0001[c0200,c0300,c0010]")
			-- bands: a raft band is placed by its raft's rank (the cards' raftRank), the raftless band by its best card
			t.expect(show(boardview.bands({
				card("c0010", "R0001", nil, nil),
				card("c0020", "R0002", nil, 40),
				card("c0030", "R0003", nil, 20),
				card("c0040", nil, 30),
				card("c0050", nil),
			}))).toBe("R0003[c0030] -[c0040,c0050] R0002[c0020] R0001[c0010]")
			-- a blocked card moves its band first, and a blocked card is first inside its band
			t.expect(show(boardview.bands({
				card("c0010", "R0001", 1, 1),
				card("c0020", "R0002", nil, nil, true),
				card("c0021", "R0002", 5, nil),
				card("c0030", nil, 2),
			}))).toBe("R0002[c0020,c0021] R0001[c0010] -[c0030]")
			-- the same cards in any input order give the same bands
			local cards = {
				card("c0010", "R0001", 9, 9),
				card("c0020", "R0002", 1, 1),
				card("c0030", nil, 5),
				card("c0031", nil),
			}
			local reversed = {}
			for i = #cards, 1, -1 do
				table.insert(reversed, cards[i])
			end
			t.expect(show(boardview.bands(reversed))).toBe(show(boardview.bands(cards)))
			t.expect(show(boardview.bands(cards))).toBe("R0002[c0020] -[c0030,c0031] R0001[c0010]")
		end
	)

	it("AC5: board.collect gives every issue and raft its rank and orders the bands by it", function()
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(repo)
		process.exec("git", { "init", "-q", "-b", "main", repo }) -- raw: init to a named path
		fixture.git(repo, { "config", "user.name", "c0249-board" })
		fixture.git(repo, { "config", "user.email", "c0249-board@example.invalid" })
		write("z-nile/projects.toml", '[[project]]\nname = "game"\nroot = "game/.tracker"\n')
		-- three prepared issues in two rafts and one raftless; every one waits in the same column (raft)
		item(`{G}/issues/c0010`, {
			"type: chore",
			"title: A",
			"raft: R0001",
			"design: ready",
			"rank: 50",
			"status: prepared-a-b-c",
		})
		item(`{G}/issues/c0011`, {
			"type: chore",
			"title: B",
			"raft: R0002",
			"design: ready",
			"rank: 20",
			"status: prepared-a-b-c",
		})
		item(`{G}/issues/c0012`, {
			"type: chore",
			"title: C",
			"raft: R0002",
			"design: ready",
			"rank: 3",
			"status: prepared-a-b-c",
		})
		-- c0012's rank 3 was written by a move: the latest `ranked` row of its provenance.md carries moved= (a raft ignores it)
		write(
			`{G}/issues/c0012/provenance.md`,
			"# Provenance: c0012\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
				.. "| 2026-11-16 09:00 | ranked | human:Pat | rank=3; was=unset; moved=c0014 |\n"
		)
		-- c0011's rank 20 is a person's: its latest row has no moved= (an older row with one does not count)
		write(
			`{G}/issues/c0011/provenance.md`,
			"# Provenance: c0011\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
				.. "| 2026-11-16 09:00 | ranked | human:Pat | rank=11; was=unset; moved=c0014 |\n"
				.. "| 2026-11-16 09:05 | ranked | human:Pat | rank=20; was=11 |\n"
		)
		item(
			`{G}/issues/c0013`,
			{ "type: chore", "title: D", "design: ready", "rank: 30", "status: prepared-a-b-c" }
		)
		item(`{G}/issues/c0014`, { "type: chore", "title: E", "design: ready", "status: prepared-a-b-c" })
		item(
			`{G}/rafts/R0001`,
			{ "type: chore", "title: One", "issues: [c0010]", "design: ready", "status: prepared-a-b-c" }
		)
		item(`{G}/rafts/R0002`, {
			"type: chore",
			"title: Two",
			"issues: [c0011, c0012]",
			"design: ready",
			"status: prepared-a-b-c",
		})
		-- a blocked issue: first in its view whatever its rank
		item(
			`{G}/issues/c0015`,
			{ "type: chore", "title: F", "rank: 99", "design: draft", "status: blocked-a-b-c" }
		)
		item(`{G}/rafts/R0003`, {
			"type: chore",
			"title: Three",
			"issues: []",
			"design: ready",
			"rank: 5",
			"status: prepared-a-b-c",
		})
		fixture.git(repo, { "add", "-A" })
		fixture.git(repo, { "commit", "-q", "-m", "seed" })
		local m: any =
			board.collect(nil, repo, { asOf = 1794000000, refs = {}, worktrees = {}, dispatch = {} })
		local byId: { [string]: any } = {}
		for _, list in { m.issues, m.rafts } do
			for _, x in list do
				byId[x.id] = x
			end
		end
		-- the model carries each item's own rank and the one the order uses
		t.expect(byId.c0010.rank).toBe(50)
		t.expect(byId.c0012.rank).toBe(3)
		t.expect(byId.c0012.effectiveRank).toBe(3)
		t.expect(byId.R0001.rank).toBe(nil)
		t.expect(byId.R0001.effectiveRank).toBe(50) -- its member's
		t.expect(byId.R0002.effectiveRank).toBe(20) -- its best member's that a person set: c0012's moved-written 3 does not count
		t.expect(byId.R0003.rank).toBe(5)
		t.expect(byId.R0003.effectiveRank).toBe(5)
		-- the raft column: R0002 (20) before the raftless band (best card c0013, 30) before R0001 (50); inside R0002, c0011 first
		-- (inside R0002 the cards go by their own ranks: c0012 has the 3)
		t.expect(show(m.columns.game.raft)).toBe("R0002[c0012,c0011] -[c0013,c0014] R0001[c0010]")
		-- the Rafts and Issues views list their buckets in the same order, not by id text
		t.expect(table.concat(m.views.rafts["not"], " ") .. "|" .. table.concat(m.views.rafts.ready, " "))
			.toBe("|R0003 R0002 R0001")
		t.expect(table.concat(m.views.issues["not"], " ") .. "|" .. table.concat(m.views.issues.ready, " "))
			.toBe("c0015 c0013 c0014|c0012 c0011 c0010")
		-- and a blocked card is first in its column
		t.expect(show(m.columns.game.ticket)).toBe("-[c0015]")
		-- c0276's withVerdicts (lost first inside each band and bucket, a stable sort) composes with this order: a lost card
		-- goes first in its band, and the cards that are not lost keep the order of the stack
		local withLost = (board :: any).withVerdicts(m, {
			{ id = "c0014", kind = "lost", silent = 3600 },
			{ id = "c0010", kind = "lost", silent = 7200 },
		})
		t.expect(show(withLost.columns.game.raft)).toBe("R0002[c0012,c0011] -[c0014,c0013] R0001[c0010]")
		t.expect(table.concat(withLost.views.issues["not"], " ")).toBe("c0014 c0015 c0013")
		t.expect(table.concat(withLost.views.issues.ready, " ")).toBe("c0010 c0012 c0011")
		-- two lost cards in one bucket: the longest silent first, whatever their ranks
		local two = (board :: any).withVerdicts(m, {
			{ id = "c0011", kind = "lost", silent = 60 },
			{ id = "c0012", kind = "lost", silent = 9000 },
			{ id = "c0010", kind = "lost", silent = 5000 },
		})
		t.expect(table.concat(two.views.issues.ready, " ")).toBe("c0012 c0010 c0011")
	end)
end)
