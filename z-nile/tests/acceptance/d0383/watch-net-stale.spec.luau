--!strict
-- d0383: "watch-net: no pass since <date>" when origin/main has a commit that changes something outside the tracker
-- folders (the user's ruling, F8) and is more than the limit newer than the last "watch-net: the suite passed" commit.
-- The pure rules, the git reads (`watchcmd.noPassLine`), the kick's stdout and the board page are pinned, all from the
-- one constant, `watchcmd.NO_PASS_LIMIT_SECONDS`. One throwaway fixture repository under .cache/ whose history grows
-- case by case; committer dates are set with GIT_COMMITTER_DATE, the author dates differently on purpose.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local watch = require("@znile/lib/watch")
local watchcmd = require("@znile/engine/watchcmd")

local has, read = netfix.has, netfix.read
-- 2026-01-09 12:00:00 UTC: the pass commit's committer time
local PASSED = 1767960000
local LINE = "watch-net: no pass since 2026-01-09"
local LIMIT: number = watchcmd.NO_PASS_LIMIT_SECONDS or 86400
local DAY = 86400

local function stamp(epoch: number): string
	return os.date("!%Y-%m-%dT%H:%M:%S+0000", epoch) :: string
end

local function root(): string
	return (fixture.physical(".") :: string) .. "/.."
end

return t.spec("a stale pass is reported by the kick and the board", function(it)
	it("the rule: stale only when the newest source commit is more than the limit past the pass", function()
		local l = LIMIT
		t.expect(watch.noPassLine(PASSED, PASSED + l + 60, l)).toBe(LINE)
		t.expect(watch.noPassLine(PASSED, PASSED + l, l)).toBe(nil)
		t.expect(watch.noPassLine(PASSED, PASSED + l - 60, l)).toBe(nil)
		t.expect(watch.noPassLine(nil, PASSED + l + 60, l)).toBe(nil)
		t.expect(watch.noPassLine(PASSED, nil, l)).toBe(nil)
		t.expect(watch.noPassLine(PASSED, PASSED + 10, 5)).toBe(LINE)
	end)

	it("the limit is 24 hours", function()
		t.expect(watchcmd.NO_PASS_LIMIT_SECONDS).toBe(24 * 60 * 60)
	end)

	it(
		"the pass is the newest commit whose subject is exactly the pass subject, by committer time and sha",
		function()
			local log =
				"1767963600\taaa1\tsomething else\n1767960000\tbbb2\twatch-net: the suite passed\n1700000000\tccc3\twatch-net: the suite passed\n"
			local at, sha = watch.lastPass(log)
			t.expect(at).toBe(PASSED)
			t.expect(sha).toBe("bbb2")
			t.expect((watch.lastPass("1\tabc\twatch-net: the suite passed later\n"))).toBe(nil)
			t.expect((watch.lastPass(""))).toBe(nil)
		end
	)

	it("newer means a commit that changes something outside the tracker folders", function()
		local roots = { "z-nile/.tracker", "pickman/.tracker" }
		local function under(path: string): boolean
			for _, r in roots do
				if string.sub(path, 1, #r + 1) == r .. "/" then
					return true
				end
			end
			return path == "z-nile/next"
		end
		-- newest first; a commit opens with a line of char(1) and its committer time
		local function log(...: any): string
			local out = ""
			for _, c in { ... } do
				out ..= string.char(1) .. tostring(c.at) .. "\n" .. table.concat(c.paths, "\n") .. "\n"
			end
			return out
		end
		local onlyTracker = log(
			{ at = 300, paths = { "z-nile/.tracker/issues/c1/c1.md", "z-nile/next" } },
			{ at = 200, paths = { "pickman/.tracker/x.md" } }
		)
		t.expect(watch.newestSource(onlyTracker, under)).toBe(nil)
		local withSource = log({ at = 400, paths = { "z-nile/lib/a.luau", "z-nile/.tracker/x.md" } })
		t.expect(watch.newestSource(withSource .. onlyTracker, under)).toBe(400)
		-- the newest commit with a source path, not the first or the oldest
		t.expect(
			watch.newestSource(
				log(
					{ at = 300, paths = { "z-nile/.tracker/x.md" } },
					{ at = 250, paths = { "README.md" } },
					{ at = 100, paths = { "z-nile/lib/a.luau" } }
				),
				under
			)
		).toBe(250)
		t.expect(watch.newestSource("", under)).toBe(nil)
	end)

	-- one world: the pass commit comes after an old source commit; then days of tracker-only commits, a source commit just
	-- inside the limit, one just past it
	local w = netfix.world("d0383-stale", { standing = true })
	local function commit(files: { [string]: string }, message: string, committer: number, author: number?)
		for path, text in files do
			local parent = string.match(path, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{w.main}/{parent}`)
			end
			fs.writeFile(`{w.main}/{path}`, text)
		end
		fixture.git(w.f.main, { "add", "-A" })
		fixture.git(w.f.main, { "commit", "-q", "-m", message }, {
			env = { GIT_COMMITTER_DATE = stamp(committer), GIT_AUTHOR_DATE = stamp(author or PASSED) },
		})
		fixture.git(w.f.main, { "push", "-q", "origin", "HEAD:main" })
	end
	local function page(): string
		local r = trackerfix.tr(w.f, w.raft, { "board", "-O", "--out", ".cache/d0383-board.html" })
		if not r.ok then
			error(`board failed ({r.code}): {r.stderr}{r.stdout}`, 0)
		end
		return read(`{w.raft}/.cache/d0383-board.html`)
	end

	it(
		"main's history decides: no pass commit, tracker-only days, a source commit at the limit minus and plus a minute",
		function()
			local dir = w.f.main
			-- a source commit far past where the pass will be, and no pass commit at all: nothing to compare with
			commit({ ["z-nile/lib/early.luau"] = "return 1\n" }, "an early source commit", PASSED + 5 * DAY)
			t.expect(watchcmd.noPassLine(dir)).toBe(nil)
			-- the pass commit is the newest commit now: the range after it is empty
			commit(
				{ ["z-nile/watch-passed"] = "x\n" },
				"watch-net: the suite passed",
				PASSED,
				PASSED - 3 * DAY
			)
			t.expect(watchcmd.noPassLine(dir)).toBe(nil)
			-- three days of tracker-only commits (captures, approvals, the counter): not newer
			for day = 1, 3 do
				commit({
					[`z-nile/.tracker/issues/c{day}/c{day}.md`] = `day {day}\n`,
					["pickman/.tracker/backlog.md"] = `day {day}\n`,
					["z-nile/next"] = `issue {day} fixture\n`,
				}, `tracker day {day}`, PASSED + day * DAY)
			end
			t.expect(watchcmd.noPassLine(dir)).toBe(nil)
			-- a source commit 24 h minus a minute after the pass: not stale
			commit(
				{ ["z-nile/lib/late.luau"] = "return 2\n" },
				"a source commit just inside",
				PASSED + LIMIT - 60
			)
			t.expect(watchcmd.noPassLine(dir)).toBe(nil)
			t.expect(has(page(), "no pass since")).toBe(false)
		end
	)

	it(
		"a source commit 24 h plus a minute after the pass is stale: the line, on the kick's stdout and in the board",
		function()
			commit(
				{ ["z-nile/lib/later.luau"] = "return 3\n" },
				"a source commit just past",
				PASSED + LIMIT + 60
			)
			t.expect(watchcmd.noPassLine(w.f.main)).toBe(LINE)
			local r = netfix.kick(w, w.raft)
			t.expect(r.code).toBe(0)
			t.expect(has(r.stdout, `{LINE}\n`)).toBe(true)
			t.expect(has(r.stderr, "no pass since")).toBe(false)
			netfix.settle(netfix.logOf(r.stdout) :: string)
			-- shown in the page's notice, ahead of the stats and the board, not only in the data
			local html = page()
			local at = string.find(html, LINE, 1, true)
			t.expect(at ~= nil).toBe(true)
			local notice = string.find(html, 'id="notice"', 1, true)
			t.expect(notice ~= nil).toBe(true)
			t.expect((notice :: number) < (at :: number)).toBe(true)
			t.expect((at :: number) < (string.find(html, 'id="stats"', 1, true) :: number)).toBe(true)
		end
	)

	it(
		"the limit is one constant: the board calls watchcmd.noPassLine and never the pure rule with a limit of its own",
		function()
			local top = root()
			local board = read(`{top}/z-nile/engine/board.luau`)
			t.expect(has(board, "watchcmd.noPassLine")).toBe(true)
			t.expect(has(board, "watch.noPassLine")).toBe(false)
			t.expect(has(board, "lib/watch")).toBe(false)
			local literal = 0
			for _, file in { "watchcmd", "board", "main" } do
				local text = read(`{top}/z-nile/engine/{file}.luau`)
				if file ~= "watchcmd" then
					t.expect(has(text, "watch.noPassLine")).toBe(false)
				end
				for line in string.gmatch(text, "[^\n]+") do
					if
						string.find(line, "86[_]?400")
						or string.find(line, "24 * 3600", 1, true)
						or string.find(line, "24 * 60 * 60", 1, true)
					then
						literal += 1
						t.expect(file).toBe("watchcmd")
						t.expect(has(line, "NO_PASS_LIMIT_SECONDS")).toBe(true)
					end
				end
			end
			t.expect(literal).toBe(1)
		end
	)
end)
