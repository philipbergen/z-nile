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
-- the epochs of the beats origin holds for `stamp` (one branch per claim, the epoch in its commit subject)
local function epochs(stamp: string): { number }
	local out = {}
	local subjects =
		fixture.git(h.f.origin, { "for-each-ref", "--format=%(subject)", `refs/heads/hb/{stamp}` })
	for line in string.gmatch(subjects, "[^\n]+") do
		table.insert(out, tonumber(string.match(line, "(%d+)$")) :: number)
	end
	return out
end
local function tipOf(stamp: string): string
	return fixture.git(h.f.origin, { "for-each-ref", "--format=%(objectname)", `refs/heads/hb/{stamp}` })
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
# another terminal takes $FAKE_ITEM's claim over: it restamps the item on main and, in one atomic push, deletes the old
# owner's branch and creates its own
takeover() {
  o="$FAKE_OTHER"; f="$o/pickman/.tracker/issues/$FAKE_ITEM/$FAKE_ITEM.md"
  "$REAL_GIT" -C "$o" pull -q origin main
  sed -i.bak "s/^status: .*/status: $FAKE_NEWSTAMP/" "$f"; rm -f "$f.bak"
  "$REAL_GIT" -C "$o" add -A; "$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit -q -m takeover
  "$REAL_GIT" -C "$o" push -q origin HEAD:main
  tree=$("$REAL_GIT" -C "$o" rev-parse "HEAD^{tree}")
  new=$("$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit-tree "$tree" -p HEAD -m "hb $FAKE_NEWSTAMP 1")
  "$REAL_GIT" -C "$o" push -q --atomic origin ":refs/heads/hb/$FAKE_OLDSTAMP" "$new:refs/heads/hb/$FAKE_NEWSTAMP"
}
if [ "$1" = fetch ]; then
  case "$*" in
    *hb-seen*)
      if [ -f "$FAKE_DIR/raceread" ]; then rm -f "$FAKE_DIR/raceread"; takeover; fi ;;
  esac
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
    *:refs/heads/hb/*)
      if [ -f "$FAKE_DIR/racebeat" ]; then rm -f "$FAKE_DIR/racebeat"; takeover; fi ;;
  esac
fi
]]

return t.spec("c0265 takeover race and fold", function(it)
	it("sets up claims, a prepared raft to fold into, a checked item, and the shim", function()
		h = fakecli.new("c0265-edge", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0070/c0070.md`] = issue("c0070", "new-a-b-c"),
			[`{P}/c0071/c0071.md`] = issue("c0071", "new-a-b-c"),
			[`{P}/c0072/c0072.md`] = issue("c0072", "new-a-b-c"),
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
		must(zn(wt, { "status", "c0071", "preparing" }), "claim c0071")
		must(zn(wt, { "status", "c0072", "preparing" }), "claim c0072")
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

	it(
		"a beat that races a takeover is rejected by its lease: the old owner learns it lost the claim",
		function()
			local old = stampOf(`{P}/c0071/c0071.md`)
			local new = "preparing-mellow-badger-jolly"
			t.expect(tipOf(old) ~= "").toBe(true) -- the claim's first beat made its branch, and wt remembers its sha
			fs.writeFile(`{h.fakes}/racebeat`, "1")
			local due = tostring(os.time() + 1000) -- wt's entry for c0071 is due: its autobeat pushes with a lease
			local told = zn(
				wt,
				{ "lessons", "--tags" },
				{ ZN_NOW = due, FAKE_ITEM = "c0071", FAKE_OLDSTAMP = old, FAKE_NEWSTAMP = new }
			)
			t.expect(told.ok).toBe(true) -- an automatic beat never fails the command
			t.expect(has(told.stderr, `c0071's claim was taken over (now {new})`)).toBe(true)
			t.expect(stampOf(`{P}/c0071/c0071.md`)).toBe(new)
			t.expect(tipOf(old)).toBe("") -- the old owner's push was rejected: it did not recreate its branch
			t.expect(tipOf(new) ~= "").toBe(true) -- the taker's branch stands, untouched by the old owner
			t.expect(epochs(new)).toEqual({ 1 })
			t.expect(fs.isFile(`{wt}/.cache/tracker-beats/c0071`)).toBe(false) -- and its entry is gone
		end
	)

	it("a create-only beat that races a takeover deletes what it created and reports the loss", function()
		local old = stampOf(`{P}/c0072/c0072.md`)
		local new = "preparing-silver-otter-quiet"
		-- a checkout with no memory adopts the stamp it read, then the takeover lands between its main read and its hb read:
		-- it sees no branch, so its write is create-only and succeeds; the re-read of main shows another stamp
		fs.writeFile(`{h.fakes}/raceread`, "1")
		local r = zn(h.f.main, { "beat", "c0072", "--adopt" }, {
			ZN_NOW = tostring(os.time() + 1000),
			FAKE_ITEM = "c0072",
			FAKE_OLDSTAMP = old,
			FAKE_NEWSTAMP = new,
		})
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, `c0072's claim was taken over (now {new})`)).toBe(true)
		t.expect(tipOf(old)).toBe("") -- what it created was deleted again
		t.expect(tipOf(new) ~= "").toBe(true) -- the taker's branch stands
		t.expect(epochs(new)).toEqual({ 1 })
	end)

	it("fold beats for the raft it claims", function()
		must(zn(wt, { "fold", "R0030", "c0095" }), "fold")
		local stamp = stampOf("pickman/.tracker/rafts/R0030/R0030.md")
		t.expect(string.sub(stamp, 1, 10)).toBe("preparing-")
		t.expect(#epochs(stamp)).toBe(1)
	end)
end)
