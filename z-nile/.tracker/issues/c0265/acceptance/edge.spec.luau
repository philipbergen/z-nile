--!strict
-- c0265: what a blocking fixture can force with a `git` shim that acts on one named push: a takeover that meets a claim
-- restamped between its verdict and its publish is refused, and `fold` beats for the raft it claims. Instant cases.
-- Fixture under .cache/c0265-edge.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt, wt2 = "", ""
local STALE = heartbeat.STALE
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local P = "pickman/.tracker/issues"
local RESTAMP = "preparing-sunny-heron-lynx"

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
local function issue(id: string, status: string, design: string?, raft: string?): string
	local doc = string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`)
	return (string.gsub(doc, "\nraft: \n", `\nraft: {raft or ""}\n`, 1))
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local GH = '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n'
-- the shim acts on one push at a time, each armed by a marker file it removes first (answers only what it names)
local SHIM = [[#!/bin/sh
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
  esac
fi
]]

return t.spec("c0265 takeover race and fold", function(it)
	it("sets up claims, a prepared raft to fold into, a checked item, and the shim", function()
		h = fakecli.new("c0265-edge", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0070/c0070.md`] = issue("c0070", "new-a-b-c"),
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
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-edge" }), "worktree"), "%s+$", ""))
		wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-edge2" }), "worktree"), "%s+$", ""))
		must(zn(wt, { "status", "c0070", "preparing" }), "claim c0070")
	end)

	it("a takeover that meets a claim restamped between its verdict and its publish is refused", function()
		local old = stampOf(`{P}/c0070/c0070.md`)
		fs.writeFile(`{h.fakes}/race`, "1")
		local r = zn(wt2, { "status", "c0070", "preparing" }, { ZN_NOW = tostring(os.time() + 3 * STALE) })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, RESTAMP)).toBe(true) -- names the stamp it met
		t.expect(stampOf(`{P}/c0070/c0070.md`)).toBe(RESTAMP) -- the other terminal's claim stands
		t.expect(old ~= RESTAMP).toBe(true)
	end)

	it("fold beats for the raft it claims", function()
		must(zn(wt, { "fold", "R0030", "c0095" }), "fold")
		local stamp = stampOf("pickman/.tracker/rafts/R0030/R0030.md")
		t.expect(string.sub(stamp, 1, 10)).toBe("preparing-")
		t.expect(#epochs(stamp)).toBe(1)
	end)
end)
