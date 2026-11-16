--!strict
-- c0277 (review of R0100, F1): a raft that is stopped from the main checkout and readied again leaves its worktree
-- remembering the old stamp, and nothing re-adopts a claim in place (c0274). The plain lookup therefore does not hand such a
-- worktree out: it discards it like any worktree of a claim already over and returns the numbered copy, where the new
-- claim beats and `done` is allowed. A worktree whose claim is still its own, and one that remembers nothing, are returned
-- as before. Time is ZN_NOW. Fixture under .cache/c0277-reready.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local T0 = os.time()
local P = "pickman/.tracker/issues"
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local MARKER = "." .. "cache/discarded"

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
local function dir(name: string): string
	return `{h.f.main}/.worktree/{name}`
end
local function stampOf(): string
	local text = fixture.git(h.f.origin, { "show", "main:pickman/.tracker/rafts/active/R0020/R0020.md" })
	return string.match(text, "\nstatus: ([%a%-]+)\n") or error("R0020 has no stamp on origin")
end

return t.spec("c0277 a raft stopped and readied again", function(it)
	it("sets up a readied raft whose worktree adopted the claim", function()
		h = fakecli.new("c0277-reready", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0040/c0040.md`] = (string.gsub(
				string.gsub(
					trackerfix.stub("c0040", "c0040", "prepared-quiet-copper-falcon"),
					"design: draft",
					"design: ready"
				),
				"\nraft: \n",
				"\nraft: R0020\n",
				1
			)),
			[`{P}/c0040/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0020/R0020.md"] = "---\nid: R0020\ntype: chore\ntitle: Lost\nslug: lost\nsingle: false\nissues: [c0040]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0020\n",
			["pickman/.tracker/rafts/R0020/check.sh"] = CHECK,
		})
		must(zn(h.f.main, { "ready", "R0020" }, T0), "ready R0020")
		local rw = trim(must(zn(h.f.main, { "worktree", "R0020" }), "worktree"))
		t.expect(rw).toBe(dir("R0020"))
		must(zn(rw, { "beat", "R0020", "--adopt" }, T0), "adopt")
	end)

	it("a worktree whose claim is still its own is returned as before, with no notice", function()
		local r = zn(h.f.main, { "worktree", "R0020" }, T0 + 5)
		t.expect(trim(must(r, "worktree"))).toBe(dir("R0020"))
		t.expect(has(r.stderr, "remembered a claim that is over")).toBe(false)
		t.expect(fs.isDir(dir("R0020-1"))).toBe(false)
	end)

	it(
		"after stop and ready the lookup discards the old worktree and returns a numbered copy where the new claim beats",
		function()
			local s1 = stampOf()
			must(zn(h.f.main, { "stop", "R0020" }, T0 + 10), "stop")
			must(zn(h.f.main, { "ready", "R0020" }, T0 + 20), "ready again")
			local s2 = stampOf()
			t.expect(s2 ~= s1).toBe(true)
			local r = zn(h.f.main, { "worktree", "R0020" }, T0 + 30)
			local copy = trim(must(r, "worktree"))
			t.expect(copy).toBe(dir("R0020-1"))
			t.expect(has(r.stderr, "remembered a claim that is over")).toBe(true)
			t.expect(fs.isDir(dir("R0020"))).toBe(false) -- the old path is gone
			t.expect(fs.isFile(`{dir("R0020-discarded-1")}/{MARKER}`)).toBe(true)
			-- in the copy the new claim is adopted and beats; nothing is refused as taken over
			must(zn(copy, { "beat", "R0020", "--adopt" }, T0 + 40), "adopt in the copy")
			local beat =
				fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", `refs/heads/hb/{s2}` })
			t.expect(has(beat, s2)).toBe(true)
			-- the old worktree stays refused
			local old = zn(dir("R0020-discarded-1"), { "beat", "R0020" }, T0 + 50)
			t.expect(old.ok).toBe(false)
			t.expect(has(old.stderr, "this worktree was discarded")).toBe(true)
			-- asking again finds the copy, which holds the new claim: no second discard
			local again = zn(h.f.main, { "worktree", "R0020" }, T0 + 60)
			t.expect(trim(must(again, "worktree"))).toBe(copy)
			t.expect(has(again.stderr, "remembered a claim that is over")).toBe(false)
			t.expect(fs.isDir(dir("R0020-2"))).toBe(false)
		end
	)

	it(
		"a claim that ended (stopped, not readied again) is just as over, and the copy is discarded in turn",
		function()
			must(zn(h.f.main, { "stop", "R0020" }, T0 + 70), "stop")
			local r = zn(h.f.main, { "worktree", "R0020" }, T0 + 80)
			t.expect(trim(must(r, "worktree"))).toBe(dir("R0020-2"))
			t.expect(fs.isDir(dir("R0020-discarded-2"))).toBe(true)
			t.expect(fs.isDir(dir("R0020-discarded-1"))).toBe(false) -- the first discard held nothing: the stop swept it
		end
	)

	it(
		"a lookup that cannot read origin/main hands the member out as before, and discards once it can",
		function()
			must(zn(h.f.main, { "ready", "R0020" }, T0 + 90), "ready")
			local rw = trim(must(zn(h.f.main, { "worktree", "R0020" }, T0 + 91), "worktree"))
			t.expect(rw).toBe(dir("R0020-2")) -- the copy of the case above holds nothing yet
			must(zn(rw, { "beat", "R0020", "--adopt" }, T0 + 92), "adopt")
			must(zn(h.f.main, { "stop", "R0020" }, T0 + 100), "stop")
			must(zn(h.f.main, { "ready", "R0020" }, T0 + 110), "ready again")
			local gitShim = fs.readFile(`{h.bin}/git`)
			fs.writeFile(
				`{h.bin}/git`,
				(
					string.gsub(
						gitShim,
						"^#!/bin/sh\n",
						'#!/bin/sh\nif [ "$1" = fetch ] && [ -f "$FAKE_DIR/nofetch" ]; then echo "fatal: fake" >&2; exit 128; fi\n',
						1
					)
				)
			)
			fs.writeFile(`{h.fakes}/nofetch`, "1")
			local blind = zn(h.f.main, { "worktree", "R0020" }, T0 + 120)
			fs.removeFile(`{h.fakes}/nofetch`)
			fs.writeFile(`{h.bin}/git`, gitShim)
			t.expect(trim(must(blind, "worktree"))).toBe(rw) -- nothing is known to be over, so nothing is discarded
			t.expect(fs.isFile(`{rw}/` .. MARKER)).toBe(false) -- and it is not marked
			local seen = trim(must(zn(h.f.main, { "worktree", "R0020" }, T0 + 130), "worktree"))
			t.expect(seen ~= rw).toBe(true) -- read again, the old claim's worktree is discarded and a new copy is returned
			t.expect(string.match(seen, "R0020%-%d+$") ~= nil).toBe(true)
			t.expect(fs.isDir(rw)).toBe(false)
			t.expect(heartbeat.staleMember({})).toBe(false)
		end
	)
end)
