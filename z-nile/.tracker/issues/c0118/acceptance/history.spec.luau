--!strict
-- c0118 AC2: history gives every issue and raft the UTC instant it first arrived in done/ (doneAt, epoch seconds):
-- whatever offset the commit carries, unchanged by a later move between roots or by leaving and re-entering done/, and
-- unknown (nil) when the arrival is a compaction's re-add under a new id. A retired raft's folder is no arrival, and
-- rafts stay out of `closed` and `spells`. Fixture under .cache/c0118-history; git runs through @tests/lib/fixture.
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
		commit("2026-10-10T10:00:00Z", "prepared")
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
		-- the move into z-nile/.tracker: a delete and an add of each document in one commit
		move("tracker/issues/done/c0010", "z-nile/.tracker/issues/done/c0010")
		move("tracker/rafts/done/R0010", "z-nile/.tracker/rafts/done/R0010")
		move("tracker/issues/done/c0020", "z-nile/.tracker/issues/done/c0020")
		commit("2026-10-21T08:00:00Z", "move into z-nile/")
		-- a compaction: c0090 and R0090 appear in done/ under new ids in the commit that writes the map
		write("z-nile/.tracker/issues/done/c0090/c0090.md", doc("c0090", "active-a-b-c"))
		write("z-nile/.tracker/rafts/done/R0090/R0090.md", doc("R0090", "active-a-b-c"))
		write("z-nile/compaction.txt", "# compaction map\nc0901 c0090\nR0901 R0090\n")
		commit("2026-10-21T09:00:00Z", "tracker: compact ids")
		-- a raft retired into R0010 (c0116): its folder beside the lifecycle folders
		write("z-nile/.tracker/rafts/retired/R0030/R0030.md", doc("R0030", "prepared-a-b-c"))
		commit("2026-10-21T10:00:00Z", "recombine: R0030 retired into R0010")
		-- a squash adds an emergent issue straight into done/
		write("z-nile/.tracker/issues/done/c0040/c0040.md", doc("c0040", "active-m-n-o"))
		commit("2026-10-21T11:00:00Z", "R0040: land (#2)")
		parsed = history.parse(fixture.git(repo, history.logArgs(ROOTS)), ROOTS)
		t.expect(parsed ~= nil).toBe(true)
	end)

	it("dates an issue's and a raft's landing at the commit's instant in UTC", function()
		local landing = stats.seconds("2026-10-19T06:30:00Z")
		t.expect(parsed.doneAt.c0010).toBe(landing)
		t.expect(parsed.doneAt.R0010).toBe(landing)
		t.expect(parsed.doneAt.c0040).toBe(stats.seconds("2026-10-21T11:00:00Z"))
	end)

	it("keeps the first landing across a move between roots and a later return to done/", function()
		t.expect(parsed.doneAt.c0020).toBe(stats.seconds("2026-10-19T07:00:00Z"))
	end)

	it("an arrival in a commit that writes the compaction map is no landing time", function()
		t.expect(parsed.doneAt.c0090).toBe(nil)
		t.expect(parsed.doneAt.R0090).toBe(nil)
		t.expect(parsed.closed.c0090 ~= nil).toBe(true) -- the close day stats reads is unchanged
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
