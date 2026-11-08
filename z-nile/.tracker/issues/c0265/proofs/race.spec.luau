--!strict
-- f0265: real-time proofs, run once by check.sh and never promoted (a spec waits for nothing): `beat --watch` says a
-- failed tick and keeps beating, stops when its claim is restamped, a long `check` beats while it runs, and a hung
-- remote is bounded. Fixture under .cache/f0265-race.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt = ""
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
	local refs = fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", `refs/zn/hb/{stamp}/` })
	for line in string.gmatch(refs, "[^\n]+") do
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
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local GH = '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n'
-- the shim acts on one push at a time, each armed by a marker file it removes first (answers only what it names)
local SHIM = [[#!/bin/sh
if [ "$1" = ls-remote ]; then
  echo x >> "$FAKE_DIR/lscalls"
  [ -f "$FAKE_DIR/lshang" ] && sleep 30
fi
if [ "$1" = push ]; then
  case "$*" in
    *:refs/heads/main*)
      if [ -f "$FAKE_DIR/race" ]; then
        rm -f "$FAKE_DIR/race"
        o="$FAKE_OTHER"; f="$o/pickman/.tracker/issues/c0070/c0070.md"
        "$REAL_GIT" -C "$o" pull -q origin main
        sed -i.bak "s/^status: .*/status: preparing-sunny-heron-lynx/" "$f"; rm -f "$f.bak"
        "$REAL_GIT" -C "$o" add -A; "$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit -q -m restamp
        "$REAL_GIT" -C "$o" push -q origin HEAD:main
      fi ;;
    *:refs/zn/hb/*)
      if [ -f "$FAKE_DIR/pushfail" ]; then rm -f "$FAKE_DIR/pushfail"; echo "fatal: fake beat push failure" >&2; exit 1; fi
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

return t.spec("f0265 real-time proofs", function(it)
	it("sets up claims, a prepared raft to fold into, a checked item, and the shim", function()
		h = fakecli.new("f0265-race", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0070/c0070.md`] = issue("c0070", "new-a-b-c"),
			[`{P}/c0080/c0080.md`] = issue("c0080", "new-a-b-c"),
			[`{P}/c0085/c0085.md`] = issue("c0085", "new-a-b-c"),
			[`{P}/c0090/c0090.md`] = issue("c0090", "new-a-b-c"),
			-- c0090's check runs while a beat must arrive: it polls origin for a beat dated two seconds into the run
			[`{P}/c0090/check.sh`] = table.concat({
				"#!/usr/bin/env bash",
				"start=$(date +%s); i=0",
				"while [ $i -lt 15 ]; do",
				"  for r in $(git ls-remote origin \"refs/zn/hb/*\" | awk '{print $2}'); do",
				'    case "$r" in *"$STAMP"/*) [ "${r##*/}" -ge $((start+2)) ] && { echo seen > "$FAKE_DIR/check-beat"; exit 0; } ;; esac',
				"  done",
				"  sleep 1; i=$((i+1))",
				"done",
				"exit 1",
				"",
			}, "\n"),
			[`{P}/c0095/c0095.md`] = issue("c0095", "prepared-quiet-copper-falcon", "ready"),
			[`{P}/c0095/check.sh`] = CHECK,
			[`{P}/c0096/c0096.md`] = issue("c0096", "prepared-quiet-copper-falcon", "ready", "R0030"),
			[`{P}/c0096/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0030/R0030.md"] = `---\nid: R0030\ntype: chore\ntitle: Fold\nslug: fold\nsingle: false\nissues: [c0096]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0030\n`,
			["pickman/.tracker/rafts/R0030/check.sh"] = CHECK,
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
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "f0265-race" }), "worktree"), "%s+$", ""))
		for _, id in { "c0070", "c0080", "c0085", "c0090" } do
			must(zn(wt, { "status", id, "preparing" }), `claim {id}`)
		end
	end)

	it("sets up claims, a prepared raft to fold into, a checked item, and the shim", function()
		h = fakecli.new("f0265-race", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0070/c0070.md`] = issue("c0070", "new-a-b-c"),
			[`{P}/c0080/c0080.md`] = issue("c0080", "new-a-b-c"),
			[`{P}/c0085/c0085.md`] = issue("c0085", "new-a-b-c"),
			[`{P}/c0090/c0090.md`] = issue("c0090", "new-a-b-c"),
			-- c0090's check runs while a beat must arrive: it polls origin for a beat dated two seconds into the run
			[`{P}/c0090/check.sh`] = table.concat({
				"#!/usr/bin/env bash",
				"start=$(date +%s); i=0",
				"while [ $i -lt 15 ]; do",
				"  for r in $(git ls-remote origin \"refs/zn/hb/*\" | awk '{print $2}'); do",
				'    case "$r" in *"$STAMP"/*) [ "${r##*/}" -ge $((start+2)) ] && { echo seen > "$FAKE_DIR/check-beat"; exit 0; } ;; esac',
				"  done",
				"  sleep 1; i=$((i+1))",
				"done",
				"exit 1",
				"",
			}, "\n"),
			[`{P}/c0095/c0095.md`] = issue("c0095", "prepared-quiet-copper-falcon", "ready"),
			[`{P}/c0095/check.sh`] = CHECK,
			[`{P}/c0096/c0096.md`] = issue("c0096", "prepared-quiet-copper-falcon", "ready", "R0030"),
			[`{P}/c0096/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0030/R0030.md"] = `---\nid: R0030\ntype: chore\ntitle: Fold\nslug: fold\nsingle: false\nissues: [c0096]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0030\n`,
			["pickman/.tracker/rafts/R0030/check.sh"] = CHECK,
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
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "f0265-race" }), "worktree"), "%s+$", ""))
		for _, id in { "c0070", "c0080", "c0085", "c0090" } do
			must(zn(wt, { "status", id, "preparing" }), `claim {id}`)
		end
	end)

	it("beat --watch says a failed tick and keeps beating", function()
		local stamp = stampOf(`{P}/c0080/c0080.md`)
		local started = os.time()
		fs.writeFile(`{h.fakes}/pushfail`, "1")
		local r = zn(
			wt,
			{ "beat", "c0080", "--watch" },
			{ ZN_BOUNDED_DEADLINE = tostring(started + 8), ZN_BEAT_EVERY = "1" }
		)
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "fake beat push failure")).toBe(true)
		t.expect(newest(stamp) >= started + 2).toBe(true) -- a later tick beat
		t.expect(newest(stamp) <= os.time()).toBe(true)
	end)

	it("beat --watch stops, saying why, when its claim is restamped", function()
		local started = os.time()
		fs.writeFile(`{h.fakes}/restamp`, "1")
		local r = zn(
			wt,
			{ "beat", "c0085", "--watch" },
			{ ZN_BOUNDED_DEADLINE = tostring(started + 20), ZN_BEAT_EVERY = "1" }
		)
		t.expect(r.ok).toBe(true)
		t.expect(os.time() - started < 10).toBe(true) -- well before its bound
		t.expect(has(r.stderr .. r.stdout, "taken over")).toBe(true)
		t.expect(#epochs("preparing-mellow-badger-jolly")).toBe(0) -- it never beat the new claim
	end)

	it("a long outer command beats while it runs", function()
		local stamp = stampOf(`{P}/c0090/c0090.md`)
		local r = zn(wt, { "check", "c0090" }, { ZN_BEAT_EVERY = "1", STAMP = stamp })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{h.fakes}/check-beat`)).toBe(true)
	end)

	it(
		"a hung remote is bounded: status returns, warns, and a failed beat attempt is not retried inside the interval",
		function()
			fs.writeFile(`{h.fakes}/lshang`, "1")
			local started = os.time()
			local r = zn(
				h.f.main,
				{ "status" },
				{ ZN_NOW = tostring(os.time() + 5 * STALE), ZN_NET_SECONDS = "1" }
			)
			t.expect(r.ok).toBe(true)
			t.expect(os.time() - started < 20).toBe(true)
			t.expect(has(r.stderr, "heartbeats unreadable")).toBe(true)
			-- in a worktree that holds claims, a command that judges nothing makes one failed attempt per claim and no more
			local function calls(): number
				local text = if fs.isFile(`{h.fakes}/lscalls`) then fs.readFile(`{h.fakes}/lscalls`) else ""
				return #string.gsub(text, "[^x]", "")
			end
			local before = calls()
			must(
				zn(
					wt,
					{ "lessons", "--tags" },
					{ ZN_NOW = tostring(os.time() + 6 * STALE), ZN_NET_SECONDS = "1" }
				),
				"lessons in the worktree"
			)
			local first = calls()
			t.expect(first > before).toBe(true)
			must(
				zn(
					wt,
					{ "lessons", "--tags" },
					{ ZN_NOW = tostring(os.time() + 6 * STALE + 10), ZN_NET_SECONDS = "1" }
				),
				"lessons again"
			)
			t.expect(calls()).toBe(first) -- inside the interval: no new attempt
			fs.removeFile(`{h.fakes}/lshang`)
		end
	)
end)
