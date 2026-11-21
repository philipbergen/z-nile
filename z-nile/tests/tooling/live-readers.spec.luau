--!strict
-- f0424 step 4, the readers: `./zn work status` shows the live layer's workers (and today's lines, unchanged, without
-- them), and liveview, which turns the snapshot into those lines and the page's record. Fixture: .cache/live-readers; the
-- daemon is a fake znlive that answers `workers` and `claims` with fixed JSON.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local liveview = require("@znile/engine/liveview")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- times relative to now, so "today" and "yesterday" mean the same whenever the spec runs
local NOW = os.time()
local HEARD, HEARD2, SINCE = NOW - 60, NOW - 120, NOW - 3 * 86400
local WORKERS = string.format(
	'{"ok":true,"seq":9,"workers":[{"id":"claude-1@h","cli":"claude","state":"working","heard":%d,"started":%d,"can":["design/hard","code/hard","code-review/hard","answer/normal","done/normal","draft/easy"]},{"id":"grok-2@h","cli":"grok","state":"idle","heard":%d,"started":%d}]}',
	HEARD,
	NOW - 9000,
	HEARD2,
	NOW - 9000
)
local CLAIMS = string.format(
	'{"ok":true,"seq":9,"claims":[{"unit":"R0099","activity":"code-review","worker":"claude-1@h","since":%d}]}',
	SINCE
)

return t.spec("f0424 the readers: work status and liveview", function(it)
	it("pacific time follows the US daylight rule", function()
		t.expect(liveview.pacific(1795262040, 1795262040)).toBe("03:54 PST") -- 2026-11-21
		t.expect(liveview.pacific(1784390400, 1784390400)).toBe("09:00 PDT") -- 2026-07-18 16:00 UTC
		-- 2026-03-08 09:59:59 UTC is still PST (01:59), 10:00 UTC is 03:00 PDT
		t.expect(liveview.pacific(1772963999, 1772963999)).toBe("01:59 PST")
		t.expect(liveview.pacific(1772964000, 1772964000)).toBe("03:00 PDT")
		-- 2026-11-01 08:59:59 UTC is 01:59 PDT, 09:00 UTC is 01:00 PST
		t.expect(liveview.pacific(1793523599, 1793523599)).toBe("01:59 PDT")
		t.expect(liveview.pacific(1793523600, 1793523600)).toBe("01:00 PST")
	end)

	it("a worker's capabilities are a few words, not thirty pairs", function()
		t.expect(liveview.canSummary({})).toBe("can: nothing recorded")
		t.expect(liveview.canSummary({ "code/hard", "code/easy", "design/hard" }))
			.toBe("can code,design (3 pairs)")
		local many: { string } = {}
		for _, a in { "a", "b", "c", "d", "e", "f" } do
			table.insert(many, `{a}/hard`)
			table.insert(many, `{a}/easy`)
		end
		t.expect(liveview.canSummary(many)).toBe("can a,b,c,d, +2 more (12 pairs)")
	end)

	it(
		"the worker lines say id, cli, one state word, what it holds and since when (with the date when it is not today), when it was heard, and what it can do",
		function()
			local now = 1795262040 -- 2026-11-21 03:54 PST
			local live = liveview.slim({
				ok = true,
				at = now,
				workers = {
					{ id = "grok-2@h", cli = "grok", state = "idle", heard = 1795261900, can = {} },
					{
						id = "claude-1@h",
						cli = "claude",
						state = "working",
						heard = 1795262000,
						can = { "code/hard" },
					},
					{ id = "old-3@h", cli = "kimi", state = "lost", heard = 1795100000, can = {} },
				},
				claims = {
					{ unit = "R0099", activity = "code-review", worker = "claude-1@h", since = 1795261000 },
					{ unit = "c0001", activity = "code", worker = "old-3@h", since = 1795100000 },
				},
			}) :: liveview.Live
			t.expect(liveview.workerLines(live)).toEqual({
				"claude-1@h claude holds R0099 code-review since 03:36 PST heard 03:53 PST can code (1 pair)",
				"grok-2@h grok idle heard 03:51 PST can: nothing recorded",
				"old-3@h kimi lost, holds c0001 code since Nov 19 06:53 PST heard Nov 19 06:53 PST can: nothing recorded",
			})
			t.expect(liveview.pacific(1795262040, 1795262040 + 86400)).toBe("Nov 21 03:54 PST")
			t.expect(liveview.slim({ ok = false })).toBe(nil)
		end
	)

	local f: trackerfix.Fixture
	local bin, log = "", ""
	local env: { [string]: string } = {}

	local function status(extra: { [string]: string }?): fixture.Result
		local e = table.clone(env)
		local more: { [string]: string } = extra or {}
		for k, v in more do
			e[k] = v
		end
		return trackerfix.tr(f, f.main, { "work", "status" }, e)
	end

	it("sets up a repository and a fake znlive", function()
		f = trackerfix.new("live-readers")
		bin, log = `{f.base}/znlive`, `{f.base}/calls.log`
		fs.writeFile(
			bin,
			`#!/bin/sh\necho "$*" >> "{log}"\ncase "$1" in\n  workers) echo '{WORKERS}' ;;\n  claims) echo '{CLAIMS}' ;;\n  *) exit 3 ;;\nesac\n`
		)
		process.exec("chmod", { "+x", bin })
		env = { ZN_LIVE = "", ZN_LIVE_BIN = bin, ZN_LIVE_ROOT = "" }
	end)

	it("with two workers work status prints today's lines, then one line per worker", function()
		local r = status()
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "nobody holds a raft")).toBe(true)
		t.expect(
			has(
				r.stdout,
				`claude-1@h claude holds R0099 code-review since {liveview.pacific(SINCE, NOW)} heard {liveview.pacific(
					HEARD,
					NOW
				)} can `
			)
		).toBe(true)
		t.expect(string.find(r.stdout, "since %a%a%a %d") ~= nil).toBe(true) -- three days ago: it carries its date
		t.expect(has(r.stdout, `grok-2@h grok idle heard {liveview.pacific(HEARD2, NOW)}`)).toBe(true)
		-- a read: it asked for workers and claims and nothing else (it never starts a daemon)
		for line in string.gmatch(fs.readFile(log), "[^\n]+") do
			t.expect(line == "workers" or line == "claims").toBe(true)
		end
	end)

	it("with no workers, or an unavailable layer, the output is today's, unchanged", function()
		fs.writeFile(
			bin,
			'#!/bin/sh\ncase "$1" in\n  workers) echo \'{"ok":true,"seq":1,"workers":[]}\' ;;\n  claims) echo \'{"ok":true,"seq":1,"claims":[]}\' ;;\n  *) exit 3 ;;\nesac\n'
		)
		local empty = status()
		fs.writeFile(bin, "#!/bin/sh\nexit 3\n")
		local dead = status()
		local off = status({ ZN_LIVE = "off" })
		local nobin = status({ ZN_LIVE_BIN = `{f.base}/missing` })
		for _, r in { empty, dead, off, nobin } do
			t.expect(r.ok).toBe(true)
			t.expect(r.stdout).toBe("nobody holds a raft\n")
			t.expect(r.stderr).toBe("")
		end
	end)
end)
