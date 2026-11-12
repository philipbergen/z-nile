--!strict
-- c0275: real-time proofs, run once by check.sh and never promoted (a spec waits for nothing). A long `./zn` command beats
-- the claims its worktree holds while it runs (not only before or after): a check that waits for a beat of its own claim
-- gets one. A hung remote costs a worktree's command one bounded attempt per claim and no more inside the interval.
-- Fixture under .cache/c0275-long.
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
	local env: { [string]: string } = { FAKE_DIR = h.fakes, PATH = `{h.bin}:{process.env.PATH}` }
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
local function lines(file: string): number
	local text = if fs.isFile(file) then fs.readFile(file) else ""
	return #string.gsub(text, "[^\n]", "")
end
local function issue(id: string, status: string): string
	return trackerfix.stub(id, id, status)
end
-- the check waits (up to 20 s) for two pushes of heartbeat branches after the count it is given: the command's own beat before
-- its handler is one, so only a tick while the check runs is the second
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: a beat lands while this check runs" bash -c \'i=0; while [ $i -lt 20 ]; do '
	.. 'n=$(wc -l < "$FAKE_DIR/beatpush" 2>/dev/null || echo 0); '
	.. 'if [ "${n// /}" -gt "$((BEFORE+1))" ]; then echo seen > "$FAKE_DIR/check-beat"; exit 0; fi; '
	.. "sleep 1; i=$((i+1)); done; exit 1'\nfinish\n"
local SHIM = '#!/bin/sh\nif [ "$1" = push ]; then case "$*" in *":refs/heads/hb/"*) echo p >> "$FAKE_DIR/beatpush";; esac; fi\n'
	.. 'if [ "$1" = fetch ]; then case "$*" in *hb-seen*) echo x >> "$FAKE_DIR/lscalls"; [ -f "$FAKE_DIR/lshang" ] && sleep 120;; esac; fi\n'

return t.spec("c0275 real-time proofs: long commands and a hung remote", function(it)
	it("sets up a claimed worktree and the shim", function()
		h = fakecli.new("c0275-long", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0090/c0090.md`] = issue("c0090", "new-a-b-c"),
			[`{P}/c0090/check.sh`] = CHECK,
			[`{P}/c0091/c0091.md`] = issue("c0091", "new-a-b-c"),
		})
		fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		fs.writeFile(`{h.bin}/git`, (string.gsub(fs.readFile(`{h.bin}/git`), "^#!/bin/sh\n", SHIM, 1)))
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-long" }), "worktree"), "%s+$", ""))
		must(zn(wt, { "status", "c0090", "preparing" }), "claim c0090")
		must(zn(wt, { "status", "c0091", "preparing" }), "claim c0091")
	end)

	it("a long outer command beats while it runs", function()
		local before = lines(`{h.fakes}/beatpush`)
		local r = zn(wt, { "check", "c0090" }, { ZN_BEAT_EVERY = "1", BEFORE = tostring(before) })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{h.fakes}/check-beat`)).toBe(true)
		t.expect(lines(`{h.fakes}/beatpush`) > before).toBe(true)
	end)

	it(
		"a hung remote costs one bounded attempt per interval, said, and the command still succeeds",
		function()
			fs.writeFile(`{h.fakes}/lshang`, "1")
			local before = lines(`{h.fakes}/lscalls`)
			local started = os.time()
			local later = os.time() + 6 * STALE
			local r = zn(wt, { "lessons", "--tags" }, { ZN_NOW = tostring(later), ZN_NET_SECONDS = "1" })
			t.expect(r.ok).toBe(true)
			t.expect(os.time() - started < 30).toBe(true) -- the hung call (120 s) was cut at the 1 s net limit, per claim
			t.expect(has(r.stderr, "beat: c0090:") or has(r.stderr, "beat: c0091:")).toBe(true)
			local first = lines(`{h.fakes}/lscalls`)
			t.expect(first > before).toBe(true)
			-- inside the interval nothing more is tried: the failed attempt advanced each claim's mark
			must(
				zn(wt, { "lessons", "--tags" }, { ZN_NOW = tostring(later + 10), ZN_NET_SECONDS = "1" }),
				"lessons again"
			)
			t.expect(lines(`{h.fakes}/lscalls`)).toBe(first)
			fs.removeFile(`{h.fakes}/lshang`)
		end
	)
end)
