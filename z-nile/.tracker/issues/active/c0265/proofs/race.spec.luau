--!strict
-- c0265: real-time proofs, run once by check.sh and never promoted (a spec waits for nothing): `beat --watch` says a
-- failed tick and keeps beating, stops when its claim is restamped, and a hung remote is bounded: the heartbeat read
-- gives up after ZN_NET_SECONDS, says so, and nothing is called lost. Fixture under .cache/c0265-race.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt, wtB = "", "" -- wt keeps its claims; wtB makes c0085 and runs nothing after it is restamped
local STALE = heartbeat.STALE
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local P = "pickman/.tracker/issues"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		FAKE_OTHER = h.f.other,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
	}
	for k, v in (extra or {}) :: { [string]: string } do
		env[k] = v
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function stampOf(path: string): string
	local text = fixture.git(h.f.origin, { "show", `main:{path}` })
	return string.match(text, "\nstatus: ([%a%-]+)\n") or error(`{path} has no status on origin`)
end
-- the epochs of the beats origin holds for `stamp`
local function epochs(stamp: string): { number }
	local out = {}
	local subjects =
		fixture.git(h.f.origin, { "for-each-ref", "--format=%(subject)", `refs/heads/hb/{stamp}` })
	for line in string.gmatch(subjects, "[^\n]+") do
		table.insert(out, tonumber(string.match(line, "(%d+)$")) :: number)
	end
	return out
end
local function newest(stamp: string): number
	local n = 0
	for _, e in epochs(stamp) do
		n = math.max(n, e)
	end
	return n
end
local function issue(id: string, status: string, design: string?, raft: string?): string
	local doc = string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`)
	return (string.gsub(doc, "\nraft: \n", `\nraft: {raft or ""}\n`, 1))
end
local GH =
	'#!/bin/sh\nif [ "$1" = pr ] && [ "$2" = list ]; then\n  [ -f "$FAKE_DIR/ghhang" ] && sleep 120\n  echo "[]"\nfi\nexit 0\n'
-- the shim acts on one push at a time, each armed by a marker file it removes first (answers only what it names)
local SHIM = [[#!/bin/sh
if [ "$1" = fetch ]; then
  case "$*" in
    *hb-seen*)
      echo x >> "$FAKE_DIR/lscalls"
      [ -f "$FAKE_DIR/lshang" ] && sleep 120 ;;
    *"origin main"*)
      [ -f "$FAKE_DIR/mainhang" ] && sleep 120
      if [ -f "$FAKE_DIR/mainfail" ]; then
        read skip fail < "$FAKE_DIR/mainfail"
        if [ "$skip" -gt 0 ]; then echo "$((skip-1)) $fail" > "$FAKE_DIR/mainfail"
        elif [ "$fail" -gt 0 ]; then echo "0 $((fail-1))" > "$FAKE_DIR/mainfail"; echo "fatal: fake main fetch failure" >&2; exit 1; fi
      fi ;;
  esac
fi
if [ "$1" = push ]; then
  case "$*" in
    *:refs/heads/hb/*)
      [ -f "$FAKE_DIR/pushhang" ] && sleep 120
      if [ -f "$FAKE_DIR/pushfail" ]; then
        n=$(cat "$FAKE_DIR/pushfail")
        if [ "$n" -gt 0 ]; then echo $((n-1)) > "$FAKE_DIR/pushfail"; echo "fatal: fake beat push failure" >&2; exit 1; fi
      fi
      if [ -f "$FAKE_DIR/restamp" ]; then
        rm -f "$FAKE_DIR/restamp"
        o="$FAKE_OTHER"; f="$o/pickman/.tracker/issues/c0085/c0085.md"
        "$REAL_GIT" -C "$o" pull -q origin main
        sed -i.bak "s/^status: .*/status: preparing-mellow-badger-jolly/" "$f"; rm -f "$f.bak"
        "$REAL_GIT" -C "$o" add -A; "$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit -q -m restamp
        "$REAL_GIT" -C "$o" push -q origin HEAD:main
      fi ;;
  esac
fi
]]

return t.spec("c0265 real-time proofs", function(it)
	it("sets up claims and the shim", function()
		h = fakecli.new("c0265-race", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0080/c0080.md`] = issue("c0080", "new-a-b-c"),
			[`{P}/c0085/c0085.md`] = issue("c0085", "new-a-b-c"),
		})
		fs.writeFile(`{h.bin}/gh`, GH)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		local real = string.match(fs.readFile(`{h.bin}/git`), 'exec "([^"]+)" "%$@"')
			or error("no real git in the shim")
		fs.writeFile(
			`{h.bin}/git`,
			(
				string.gsub(
					fs.readFile(`{h.bin}/git`),
					"^#!/bin/sh\n",
					"#!/bin/sh\nREAL_GIT='" .. real .. "'; export REAL_GIT\n" .. string.sub(SHIM, 11),
					1
				)
			)
		)
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-race" }), "worktree"), "%s+$", ""))
		wtB = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-race-b" }), "worktree"), "%s+$", ""))
		must(zn(wt, { "status", "c0080", "preparing" }), "claim c0080")
		must(zn(wtB, { "status", "c0085", "preparing" }), "claim c0085")
	end)

	it("beat --watch says a failed tick and keeps beating", function()
		local stamp = stampOf(`{P}/c0080/c0080.md`)
		local started = os.time()
		fs.writeFile(`{h.fakes}/pushfail`, "2") -- both tries of the first tick fail
		local r = zn(
			wt,
			{ "beat", "c0080", "--watch" },
			{ ZN_BOUNDED_DEADLINE = tostring(started + 30), ZN_BEAT_EVERY = "1" }
		)
		t.expect(r.ok).toBe(true)
		-- said by the try itself and again by the tick that gave up: twice
		local _, said = string.gsub(r.stderr, "fake beat push failure", "")
		t.expect(said).toBe(2)
		t.expect(os.time() - started < 60).toBe(true) -- it stopped itself near its bound (started + 30), however slow a tick on a loaded host
		t.expect(newest(stamp) >= started + 2).toBe(true) -- a later tick beat
		t.expect(newest(stamp) <= os.time()).toBe(true)
	end)

	it("beat --watch stops, saying why, when its claim is restamped", function()
		-- the claim already has its branch, so a beat to it succeeds and only the loop's own look at main can notice
		must(zn(wtB, { "beat", "c0085" }), "the first beat of c0085")
		local started = os.time()
		fs.writeFile(`{h.fakes}/restamp`, "1")
		local r = zn(
			wtB,
			{ "beat", "c0085", "--watch" },
			{ ZN_BOUNDED_DEADLINE = tostring(started + 90), ZN_BEAT_EVERY = "1" }
		)
		t.expect(r.ok).toBe(true)
		t.expect(os.time() - started < 60).toBe(true) -- well before its bound (started + 90)
		t.expect(has(r.stderr .. r.stdout, "taken over")).toBe(true)
		t.expect(#epochs("preparing-mellow-badger-jolly")).toBe(0) -- it never beat the new claim
	end)

	it(
		"a hung remote is bounded: lost gives up after the net limit, says so, and calls nothing lost",
		function()
			fs.writeFile(`{h.fakes}/lshang`, "1")
			local started = os.time()
			local r = zn(wt, { "lost" }, { ZN_NOW = tostring(os.time() + 5 * STALE), ZN_NET_SECONDS = "1" })
			fs.removeFile(`{h.fakes}/lshang`)
			t.expect(r.ok).toBe(false)
			t.expect(r.stdout).toBe("")
			t.expect(has(r.stderr, "heartbeats unreadable")).toBe(true)
			t.expect(os.time() - started < 60).toBe(true) -- the hung call (30 s) was cut at the 1 s net limit
			-- status still lists, unmarked, and says why
			fs.writeFile(`{h.fakes}/lshang`, "1")
			local list = zn(
				wt,
				{ "status" },
				{ ZN_NOW = tostring(os.time() + 5 * STALE), ZN_NET_SECONDS = "1" }
			)
			fs.removeFile(`{h.fakes}/lshang`)
			t.expect(list.ok).toBe(true)
			t.expect(has(list.stderr, "heartbeats unreadable")).toBe(true)
		end
	)

	it(
		"one failed fetch of main inside a --watch tick is said and the loop beats at the next tick",
		function()
			local stamp = stampOf(`{P}/c0080/c0080.md`)
			local started = os.time()
			fs.writeFile(`{h.fakes}/mainfail`, "1 1") -- the command's own first look passes, the first tick's look fails
			local r = zn(
				wt,
				{ "beat", "c0080", "--watch" },
				{ ZN_BOUNDED_DEADLINE = tostring(started + 30), ZN_BEAT_EVERY = "1" }
			)
			fs.removeFile(`{h.fakes}/mainfail`)
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stderr, "fake main fetch failure")).toBe(true)
			t.expect(newest(stamp) >= started + 2).toBe(true) -- a later tick beat
		end
	)

	it("a hung fetch of main inside beat ends at the net limit and says so", function()
		fs.writeFile(`{h.fakes}/mainhang`, "1")
		local started = os.time()
		local r = zn(wt, { "beat", "c0080" }, { ZN_NET_SECONDS = "2" })
		fs.removeFile(`{h.fakes}/mainhang`)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "timed out after 2 s")).toBe(true) -- the limit it was given, not the 10 s default
		t.expect(os.time() - started < 60).toBe(true) -- the hang is 120 s
	end)

	it("a hung push of a beat ends at the net limit and says so", function()
		fs.writeFile(`{h.fakes}/pushhang`, "1")
		local started = os.time()
		local r = zn(wt, { "beat", "c0080" }, { ZN_NET_SECONDS = "2", ZN_NOW = tostring(os.time() + 2000) })
		fs.removeFile(`{h.fakes}/pushhang`)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "timed out after 2 s")).toBe(true)
		t.expect(os.time() - started < 60).toBe(true) -- the hang is 120 s
	end)

	it(
		"a hung gh is bounded: lost says the pull requests are unreadable and nothing is called lost",
		function()
			fs.writeFile(`{h.fakes}/ghhang`, "1")
			local started = os.time()
			local r = zn(wt, { "lost" }, { ZN_NET_SECONDS = "2", ZN_NOW = tostring(os.time() + 20 * STALE) })
			fs.removeFile(`{h.fakes}/ghhang`)
			t.expect(r.ok).toBe(false)
			t.expect(r.stdout).toBe("")
			t.expect(has(r.stderr, "pull requests unreadable: timed out after 2 s")).toBe(true)
			t.expect(os.time() - started < 60).toBe(true)
		end
	)
end)
