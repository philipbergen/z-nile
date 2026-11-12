--!strict
-- c0277: a process that wakes up in a discarded worktree is told, by every ./zn command except the read-only ones and
-- `reap`, and nothing there beats: the refusal comes before the automatic beat. A marker is a marker whatever it holds, and
-- the folder it marks is untouched. Time is ZN_NOW. Fixture under .cache/c0277-guard.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local T0 = os.time()
local LATE = T0 + 3 * heartbeat.STALE
local P = "pickman/.tracker/issues"
local MARKER = "." .. "cache/discarded"
local MARKS = "." .. "cache/tracker-beats"
local wt = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
	}
	if now then
		env.ZN_NOW = tostring(now)
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
local function beatTip(stamp: string): string
	return trim(
		fixture.git(h.f.origin, { "for-each-ref", "--format=%(objectname)", `refs/heads/hb/{stamp}` })
	)
end

return t.spec("c0277 the old process in a discarded worktree", function(it)
	it("sets up a worktree that holds a claim and has a beat due, then marks it discarded", function()
		h = fakecli.new(
			"c0277-guard",
			{ [`{P}/c0010/c0010.md`] = trackerfix.stub("c0010", "c0010", "new-a-b-c") }
		)
		wt = trim(must(zn(h.f.main, { "worktree", "prep-old" }), "worktree"))
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim")
		t.expect(fs.isFile(`{wt}/{MARKS}/c0010`)).toBe(true)
		local facts: heartbeat.DiscardFacts = {
			path = wt,
			copy = `{wt}-1`,
			branch = "prep-old-discarded-1",
			base = "prep-old",
			items = { "c0010" },
			since = T0,
			pushedSha = "",
			pushed = {},
			unpushed = {},
			dirty = { "pickman/dirty.txt" },
		}
		fs.writeFile(`{wt}/{MARKER}`, heartbeat.discardText(facts))
	end)

	it(
		"every ./zn command but the read-only ones and reap refuses, saying what happened, and nothing beats first",
		function()
			local stamp =
				trim(fixture.git(wt, { "show", "origin/main:pickman/.tracker/issues/c0010/c0010.md" }))
			local held = string.match(stamp, "\nstatus: ([%a%-]+)\n") or error("no stamp")
			local tip = beatTip(held)
			local mark = fs.readFile(`{wt}/{MARKS}/c0010`)
			for _, args in
				{
					{ "lessons", "--tags" },
					{ "beat", "c0010" },
					{ "beat", "c0010", "--adopt" },
					{ "status", "c0010", "preparing" },
					{ "status", "c0010", "new" },
					{ "sync" },
					{ "worktree", "prep-other" },
					{ "done", "R0010" },
					{ "stop", "R0010" },
				}
			do
				local r = zn(wt, args, LATE) -- the beat is due at LATE: a refusal that came after the autobeat would have beaten
				t.expect(r.ok).toBe(false)
				t.expect(r.code).toBe(1)
				t.expect(has(r.stderr, "this worktree was discarded: c0010's claim was taken over"))
					.toBe(true)
				t.expect(has(r.stderr, "Clear your context and pick up something new")).toBe(true)
				t.expect(has(r.stderr, "pickman/dirty.txt")).toBe(true) -- what is kept here, listed
			end
			t.expect(beatTip(held)).toBe(tip) -- nothing beat
			t.expect(fs.readFile(`{wt}/{MARKS}/c0010`)).toBe(mark) -- and the throttle mark is as it was
			t.expect(fs.isDir(`{wt}/pickman`)).toBe(true) -- nothing was removed
		end
	)

	it("the read-only commands and reap still run there", function()
		for _, args in { { "list" }, { "audit" }, { "find", "c0010" }, { "members", "R0010" }, { "stamp" } } do
			local r = zn(wt, args, LATE)
			t.expect(has(r.stderr, "was discarded")).toBe(false)
		end
		local reap = zn(wt, { "reap", "--quiet" }, LATE)
		t.expect(has(reap.stderr, "was discarded")).toBe(false)
	end)

	it("a damaged marker still refuses, with its own text", function()
		fs.writeFile(`{wt}/{MARKER}`, "somebody wrote this by hand\n")
		local r = zn(wt, { "lessons", "--tags" }, LATE)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "was discarded")).toBe(true)
		t.expect(has(r.stderr, "somebody wrote this by hand")).toBe(true)
		fs.writeFile(`{wt}/{MARKER}`, "")
		t.expect(zn(wt, { "lessons", "--tags" }, LATE).ok).toBe(false) -- an empty marker is a marker
	end)

	it("without the marker the same worktree beats and runs as before", function()
		local before = beatTip(string.match(fs.readFile(`{wt}/{MARKS}/c0010`), "^(%S+)") :: string)
		fs.removeFile(`{wt}/{MARKER}`)
		local r = zn(wt, { "lessons", "--tags" }, LATE)
		t.expect(r.ok).toBe(true)
		t.expect(beatTip(string.match(fs.readFile(`{wt}/{MARKS}/c0010`), "^(%S+)") :: string) ~= before)
			.toBe(true) -- it beat
		t.expect(has(r.stderr, "was discarded")).toBe(false)
	end)
end)
