--!strict
-- c0118 AC2: history gives every issue and raft the UTC instant it first arrived in done/ in its current life (doneAt,
-- epoch seconds) and its latest arrival in active/ (activeAt): whatever offset the commit carries, unchanged by a move
-- between roots or by leaving and re-entering done/. A compaction (a commit that adds or changes a map's content, not
-- one that moves the map, even squashed with a landing) ends the dated life of every id on either side of a pair in the
-- map lines it adds: an id it reuses for another item loses the old landing, re-added in done/ it is undated, and a
-- later landing dates it afresh; an id it keeps keeps its dates though its document is rewritten; a map line that does
-- not parse undates every item the commit touches, with a warning. `closed` stays as it was. A retired raft's folder is no arrival, and rafts stay out of `closed` and `spells`.
-- Fixture under .cache/c0118-history; git runs through @tests/lib/fixture.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local history = require("@znile/engine/history")
local process = require("@lune/process")
local stats = require("@znile/engine/stats")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local repo = `{root}/.cache/c0118-history`
local ROOTS = { "tracker", "z-nile/.tracker" }

local function doc(id: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nstatus: {status}\n---\n\n# {id}\n`
end
local function write(path: string, text: string)
	local full = `{repo}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function commit(at: string, message: string)
	local env = { GIT_AUTHOR_DATE = at, GIT_COMMITTER_DATE = at }
	fixture.git(repo, { "add", "-A" }, { env = env })
	fixture.git(repo, { "commit", "-q", "-m", message }, { env = env })
end
local function move(from: string, to: string)
	fs.writeDir(string.match(`{repo}/{to}`, "^(.*)/[^/]+$") :: string)
	fixture.git(repo, { "mv", from, to })
end

local parsed: any = nil

return t.spec("c0118 done times", function(it)
	it("sets up a repository with dated landings, a move between roots and a compaction", function()
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(repo)
		process.exec("git", { "init", "-q", "-b", "main", repo }) -- raw: init to a named path
		fixture.git(repo, { "config", "user.name", "c0118-history" })
		fixture.git(repo, { "config", "user.email", "c0118-history@example.invalid" })
		write("tracker/issues/c0010/c0010.md", doc("c0010", "prepared-a-b-c"))
		write("tracker/rafts/R0010/R0010.md", doc("R0010", "prepared-a-b-c"))
		write("tracker/issues/c0020/c0020.md", doc("c0020", "prepared-a-b-c"))
		-- c0030 and R0050 land before the compaction; the compaction will reuse both ids for other items
		write("tracker/issues/done/c0030/c0030.md", doc("c0030", "active-a-b-c"))
		write("tracker/rafts/done/R0050/R0050.md", doc("R0050", "active-a-b-c"))
		commit("2026-10-10T10:00:00Z", "prepared")
		write("tracker/compaction.txt", "# compaction map\nc0900 c0901\nR0071 R0070\n")
		commit(
			"2026-10-10T11:00:00Z",
			"an older compaction's map, touching no item (it names R0070, which R0043's squash lands)"
		)
		-- R0060 is readied, stopped and readied again
		write("tracker/rafts/R0060/R0060.md", doc("R0060", "prepared-a-b-c"))
		commit("2026-10-11T10:00:00Z", "R0060 prepared")
		move("tracker/rafts/R0060", "tracker/rafts/active/R0060")
		commit("2026-10-12T10:00:00Z", "ready R0060")
		move("tracker/rafts/active/R0060", "tracker/rafts/R0060")
		commit("2026-10-13T10:00:00Z", "stop R0060")
		move("tracker/rafts/R0060", "tracker/rafts/active/R0060")
		commit("2026-10-14T10:00:00Z", "ready R0060 again")
		move("tracker/issues/c0010", "tracker/issues/active/c0010")
		move("tracker/rafts/R0010", "tracker/rafts/active/R0010")
		commit("2026-10-12T10:00:00Z", "ready R0010")
		-- lands on a Sunday evening in -07:00: Monday 06:30 UTC
		move("tracker/issues/active/c0010", "tracker/issues/done/c0010")
		move("tracker/rafts/active/R0010", "tracker/rafts/done/R0010")
		commit("2026-10-18T23:30:00-07:00", "R0010: land (#1)")
		-- c0020 lands, is taken back out of done/, and lands again
		move("tracker/issues/c0020", "tracker/issues/done/c0020")
		commit("2026-10-19T09:00:00+02:00", "c0020 done")
		move("tracker/issues/done/c0020", "tracker/issues/c0020")
		commit("2026-10-19T12:00:00Z", "c0020 reopened")
		move("tracker/issues/c0020", "tracker/issues/done/c0020")
		commit("2026-10-20T12:00:00Z", "c0020 done again")
		-- the move into z-nile/.tracker, squashed with the map's move and R0070's landing (c0114 and R0043 on main)
		move("tracker/issues/done/c0010", "z-nile/.tracker/issues/done/c0010")
		move("tracker/rafts/done/R0010", "z-nile/.tracker/rafts/done/R0010")
		move("tracker/issues/done/c0020", "z-nile/.tracker/issues/done/c0020")
		move("tracker/issues/done/c0030", "z-nile/.tracker/issues/done/c0030")
		move("tracker/rafts/done/R0050", "z-nile/.tracker/rafts/done/R0050")
		move("tracker/rafts/active/R0060", "z-nile/.tracker/rafts/active/R0060")
		move("tracker/compaction.txt", "z-nile/compaction.txt")
		write("z-nile/.tracker/rafts/done/R0070/R0070.md", doc("R0070", "active-a-b-c"))
		commit("2026-10-21T08:00:00Z", "R0043: move into z-nile/ (#99)")
		-- a compaction changes the map: c0090 and R0090 appear in done/ under new ids; c0030 now names another item,
		-- re-added in the backlog; R0050 now names another item, re-added in done/ at the same path
		write("z-nile/.tracker/issues/done/c0090/c0090.md", doc("c0090", "active-a-b-c"))
		write("z-nile/.tracker/rafts/done/R0090/R0090.md", doc("R0090", "active-a-b-c"))
		fixture.git(repo, { "rm", "-q", "-r", "z-nile/.tracker/issues/done/c0030" })
		write("z-nile/.tracker/issues/c0030/c0030.md", doc("c0030", "prepared-x-y-z"))
		write("z-nile/.tracker/rafts/done/R0050/R0050.md", doc("R0050", "active-x-y-z") .. "\nanother raft\n")
		-- ids the compaction keeps, whose documents it rewrites in place (they name a renumbered id)
		write(
			"z-nile/.tracker/issues/done/c0010/c0010.md",
			doc("c0010", "active-a-b-c") .. "\ndepends on c0030\n"
		)
		write(
			"z-nile/.tracker/rafts/active/R0060/R0060.md",
			doc("R0060", "prepared-a-b-c") .. "\nafter R0050\n"
		)
		write(
			"z-nile/compaction.txt",
			"# compaction map\nc0900 c0901\nR0071 R0070\nc0901 c0090\nR0901 R0090\nc0031 c0030\nR0051 R0050\n"
		)
		commit("2026-10-21T09:00:00Z", "tracker: compact ids")
		-- a raft retired into R0010 (c0116): its folder beside the lifecycle folders
		write("z-nile/.tracker/rafts/retired/R0030/R0030.md", doc("R0030", "prepared-a-b-c"))
		commit("2026-10-21T10:00:00Z", "recombine: R0030 retired into R0010")
		-- a squash adds an emergent issue straight into done/
		write("z-nile/.tracker/issues/done/c0040/c0040.md", doc("c0040", "active-m-n-o"))
		commit("2026-10-21T11:00:00Z", "R0040: land (#2)")
		-- the item now named c0030 lands
		move("z-nile/.tracker/issues/c0030", "z-nile/.tracker/issues/done/c0030")
		commit("2026-10-22T12:00:00Z", "c0030 (the new one) done")
		-- a map line that does not parse: every item the commit touches is undated
		write("z-nile/.tracker/issues/done/c0040/c0040.md", doc("c0040", "active-m-n-o") .. "\nrewritten\n")
		write(
			"z-nile/compaction.txt",
			"# compaction map\nc0900 c0901\nR0071 R0070\nc0901 c0090\nR0901 R0090\nc0031 c0030\nR0051 R0050\nnot a pair\n"
		)
		commit("2026-10-23T12:00:00Z", "a broken compaction")
		parsed = history.parse(fixture.git(repo, history.logArgs(ROOTS)), ROOTS)
		t.expect(parsed ~= nil).toBe(true)
	end)

	it("dates an issue's and a raft's landing at the commit's instant in UTC", function()
		local landing = stats.seconds("2026-10-19T06:30:00Z")
		t.expect(parsed.doneAt.c0010).toBe(landing)
		t.expect(parsed.doneAt.R0010).toBe(landing)
		t.expect(parsed.closed.c0040).toBe("2026-10-21") -- landed 2026-10-21T11:00Z; the broken map undates it (below)
	end)

	it("keeps the first landing across a move between roots and a later return to done/", function()
		t.expect(parsed.doneAt.c0020).toBe(stats.seconds("2026-10-19T07:00:00Z"))
	end)

	it("an arrival in a commit that writes the compaction map is no landing time", function()
		t.expect(parsed.doneAt.c0090).toBe(nil)
		t.expect(parsed.doneAt.R0090).toBe(nil)
		t.expect(parsed.closed.c0090 ~= nil).toBe(true) -- the close day stats reads is unchanged
	end)

	it(
		"a compaction's reuse of a done id drops the old landing, and the new item's landing dates it",
		function()
			t.expect(parsed.doneAt.c0030).toBe(stats.seconds("2026-10-22T12:00:00Z"))
			t.expect(parsed.doneAt.R0050).toBe(nil) -- re-added straight into done/: no arrival
			t.expect(parsed.closed.c0030).toBe("2026-10-10") -- Stats' close day is unchanged
		end
	)

	it("an id the compaction keeps keeps its dates, though its document is rewritten in place", function()
		t.expect(parsed.doneAt.c0010).toBe(stats.seconds("2026-10-19T06:30:00Z"))
		t.expect(parsed.activeAt.R0060).toBe(stats.seconds("2026-10-14T10:00:00Z"))
	end)

	it("a map line that does not parse undates every item the commit touches, and warns", function()
		t.expect(parsed.doneAt.c0040).toBe(nil)
		t.expect(parsed.doneAt.c0030).toBe(stats.seconds("2026-10-22T12:00:00Z")) -- not touched by that commit
		t.expect(#parsed.warnings).toBe(1)
		t.expect(string.find(parsed.warnings[1], "does not parse", 1, true) ~= nil).toBe(true)
	end)

	it("moving the map, squashed with a landing, is no compaction", function()
		t.expect(parsed.doneAt.R0070).toBe(stats.seconds("2026-10-21T08:00:00Z"))
		t.expect(parsed.doneAt.R0010).toBe(stats.seconds("2026-10-19T06:30:00Z"))
	end)

	it("keeps the latest arrival in active/, across a stop and a move between roots", function()
		t.expect(parsed.activeAt.R0060).toBe(stats.seconds("2026-10-14T10:00:00Z"))
		t.expect(parsed.activeAt.R0010).toBe(stats.seconds("2026-10-12T10:00:00Z"))
	end)

	it("a retired raft's folder is no landing, and rafts stay out of closed and spells", function()
		t.expect(parsed.doneAt.R0030).toBe(nil)
		t.expect(parsed.closed.R0010).toBe(nil)
		t.expect(parsed.spells.R0010).toBe(nil)
		t.expect(parsed.closed.c0010).toBe("2026-10-18") -- the committer's day, as before
	end)

	it("the log reads the compaction maps beside the item documents", function()
		local args = history.logArgs(ROOTS)
		t.expect(table.find(args, "z-nile/compaction.txt") ~= nil).toBe(true)
		t.expect(table.find(args, "tracker/compaction.txt") ~= nil).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(repo)
	end)
end)
