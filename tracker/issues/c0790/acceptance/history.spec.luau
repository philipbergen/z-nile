--!strict
-- c0790: history.parse derives state spells, close days and today from `git log` with history.LOG_ARGS. Fixture under
-- .cache/c0790-history: a repository whose commits carry fixed dates. Git runs through @tests/lib/fixture.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local history = require("@scripts/tracker/history")
local process = require("@lune/process")
local stats = require("@scripts/tracker/stats")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local repo = `{root}/.cache/c0790-history`

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
	fixture.git(repo, { "mv", from, to })
end

local parsed: any = nil

return t.spec("tracker history", function(it)
	it("sets up a repository with dated tracker commits", function()
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(repo)
		process.exec("git", { "init", "-q", "-b", "main", repo }) -- raw: init to a named path
		fixture.git(repo, { "config", "user.name", "history" })
		fixture.git(repo, { "config", "user.email", "history@example.invalid" })
		fs.writeDir(`{repo}/tracker/issues/done`)
		fs.writeDir(`{repo}/tracker/issues/active`)
		write("tracker/issues/f0010/f0010.md", doc("f0010", "new-a-b-c"))
		commit("2026-09-30T10:00:00Z", "new f0010")
		write("tracker/issues/c0020/c0020.md", doc("c0020", "prepared-a-b-c"))
		commit("2026-09-30T12:00:00Z", "c0020 arrives prepared")
		write("tracker/issues/f0010/f0010.md", doc("f0010", "preparing-d-e-f"))
		commit("2026-10-01T10:00:00Z", "f0010 preparing")
		-- a legacy start: the directory moves to active/ with the status line unchanged
		move("tracker/issues/c0020", "tracker/issues/active/c0020")
		commit("2026-10-01T12:00:00Z", "start c0020 (legacy)")
		write("tracker/issues/f0010/f0010.md", doc("f0010", "prepared-g-h-i"))
		commit("2026-10-01T22:00:00Z", "f0010 prepared")
		write("tracker/issues/f0010/f0010.md", doc("f0010", "active-j-k-l"))
		commit("2026-10-02T10:00:00Z", "f0010 claimed")
		move("tracker/issues/active/c0020", "tracker/issues/done/c0020")
		commit("2026-10-02T12:00:00Z", "c0020 done")
		move("tracker/issues/f0010", "tracker/issues/done/f0010")
		commit("2026-10-02T22:00:00Z", "f0010 done")
		-- an emergent issue reaches main already done (a squash adds it straight into done/)
		write("tracker/issues/done/c0040/c0040.md", doc("c0040", "active-m-n-o"))
		commit("2026-10-02T23:00:00Z", "R0010 merged with emergent c0040")
		-- c0030 is readied, stopped, readied again and finished (status changes with each move);
		-- c0050 has a legacy slug-named document, later renamed inside done/
		write("tracker/issues/c0030/c0030.md", doc("c0030", "prepared-p-q-r"))
		write("tracker/issues/c0050/c0050-legacy-slug.md", doc("c0050", "new-s-t-u"))
		commit("2026-10-03T00:00:00Z", "c0030 prepared, c0050 new")
		move("tracker/issues/c0050", "tracker/issues/done/c0050")
		commit("2026-10-03T06:00:00Z", "c0050 done (legacy name)")
		move("tracker/issues/c0030", "tracker/issues/active/c0030")
		write("tracker/issues/active/c0030/c0030.md", doc("c0030", "active-v-w-x"))
		commit("2026-10-03T12:00:00Z", "ready c0030")
		move("tracker/issues/active/c0030", "tracker/issues/c0030")
		write("tracker/issues/c0030/c0030.md", doc("c0030", "prepared-y-z-a"))
		commit("2026-10-04T00:00:00Z", "stop c0030")
		move("tracker/issues/done/c0050/c0050-legacy-slug.md", "tracker/issues/done/c0050/c0050.md")
		commit("2026-10-04T09:00:00Z", "migrate c0050 to <ID>.md")
		move("tracker/issues/c0030", "tracker/issues/active/c0030")
		write("tracker/issues/active/c0030/c0030.md", doc("c0030", "active-b-c-d"))
		commit("2026-10-04T12:00:00Z", "ready c0030 again")
		move("tracker/issues/active/c0030", "tracker/issues/done/c0030")
		commit("2026-10-05T12:00:00Z", "c0030 done")
		parsed = history.parse(fixture.git(repo, history.LOG_ARGS))
	end)

	it("parse turns status stamps into spells and the move to done into a close day", function()
		t.expect(parsed.closed.f0010).toBe("2026-10-02")
		local d = stats.durations({
			{
				id = "f0010",
				type = "feature",
				opened = "2026-09-30",
				closed = "2026-10-02",
				spells = parsed.spells.f0010,
			},
		})
		t.expect(d.new.all).toEqual({ n = 1, mean = 1.0, median = 1.0 })
		t.expect(d.preparing.all).toEqual({ n = 1, mean = 0.5, median = 0.5 })
		t.expect(d.prepared.all).toEqual({ n = 1, mean = 0.5, median = 0.5 })
		t.expect(d.active.all).toEqual({ n = 1, mean = 0.5, median = 0.5 })
		-- the move into done/ re-adds the whole file, old status line included: it must not open a new spell
		for _, s in parsed.spells.f0010 do
			t.expect(s.to ~= nil).toBe(true)
		end
	end)

	it("a legacy start's move to active starts an active spell", function()
		t.expect(parsed.closed.c0020).toBe("2026-10-02")
		local d = stats.durations({
			{
				id = "c0020",
				type = "chore",
				opened = "2026-09-30",
				closed = "2026-10-02",
				spells = parsed.spells.c0020,
			},
		})
		t.expect(d.prepared.all).toEqual({ n = 1, mean = 1.0, median = 1.0 }) -- 09-30 12:00 to 10-01 12:00
		t.expect(d.active.all).toEqual({ n = 1, mean = 1.0, median = 1.0 }) -- 10-01 12:00 to 10-02 12:00
	end)

	it("a move whose status changes starts a spell of the new status (ready, stop, ready, done)", function()
		t.expect(parsed.closed.c0030).toBe("2026-10-05")
		local d = stats.durations({
			{
				id = "c0030",
				type = "chore",
				opened = "2026-10-03",
				closed = "2026-10-05",
				spells = parsed.spells.c0030,
			},
		})
		t.expect(d.prepared.all).toEqual({ n = 2, mean = 0.5, median = 0.5 }) -- 10-03 00:00-12:00, 10-04 00:00-12:00
		t.expect(d.active.all).toEqual({ n = 2, mean = 0.75, median = 0.75 }) -- 12 h, then 10-04 12:00 to 10-05 12:00
	end)

	it("a close day is the first add of an item's document into done/, however it got there", function()
		t.expect(parsed.closed.c0040).toBe("2026-10-02") -- added straight into done/
		t.expect(parsed.closed.c0050).toBe("2026-10-03") -- the later rename inside done/ does not move it
	end)

	it("today is the last commit's day", function()
		t.expect(parsed.today).toBe("2026-10-05")
	end)
end)
