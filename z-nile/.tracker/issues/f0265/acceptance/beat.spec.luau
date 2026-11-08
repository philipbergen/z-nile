--!strict
-- f0265: a beat is a ref (refs/zn/hb/<claim stamp>/<epoch>) pushed to origin outside main: a claim writes the first
-- one, `beat` writes the next from any checkout and deletes the older, `ready` beats for the raft it claims, and `beat`
-- refuses what nobody claims. Time is ZN_NOW (epoch seconds), so no case waits. Fixture under .cache/f0265-beat.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt = "" -- a worktree of the fixture
local T0 = os.time()

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?): fixture.Result
	local env: { [string]: string } = {}
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
-- the beat refs on origin, as { stamp, epoch } read from the remote's own ref names
local function beats(): { { stamp: string, epoch: number } }
	local out = {}
	for line in
		string.gmatch(
			fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", "refs/zn/hb/" }),
			"[^\n]+"
		)
	do
		local stamp, epoch = string.match(line, "^refs/zn/hb/([%a%-]+)/(%d+)$")
		table.insert(out, { stamp = stamp :: string, epoch = tonumber(epoch) :: number })
	end
	return out
end
local function stampOf(id: string, path: string): string
	local text = fixture.git(h.f.origin, { "show", `main:{path}` })
	return string.match(text, "\nstatus: ([%a%-]+)\n") or error(`{id} has no status on origin`)
end
local function issue(id: string, status: string, design: string?): string
	return (string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`))
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Beat\nslug: beat\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local P = "pickman/.tracker/issues"

return t.spec("f0265 a beat is a ref outside main", function(it)
	it("sets up a tracker with new issues, a prepared raft and a claimed issue with fake CLIs", function()
		h = fakecli.new("f0265-beat", {
			[".gitignore"] = ".cache/\n.worktree/\nprompt.md\n",
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
			[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
			[`{P}/c0030/c0030.md`] = issue("c0030", "new-a-b-c"),
			[`{P}/c0040/c0040.md`] = issue("c0040", "prepared-quiet-copper-falcon", "ready"),
			[`{P}/c0040/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0040"),
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			[`{P}/c0050/c0050.md`] = issue("c0050", "preparing-lucky-violet-heron"),
		})
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "f0265-beat" }), "worktree"), "%s+$", ""))
	end)

	it("a claim writes the first beat as a ref, and main only gets the claim", function()
		local main = fixture.git(h.f.origin, { "rev-parse", "main" })
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		local stamp = stampOf("c0010", `{P}/c0010/c0010.md`)
		local list = beats()
		t.expect(#list).toBe(1)
		t.expect(list[1].stamp).toBe(stamp)
		t.expect(list[1].epoch).toBe(T0)
		-- the claim is one commit on main and the beat is not: nothing else moved, no branch was made for it
		t.expect(fixture.git(h.f.origin, { "rev-list", "--count", `{main}..main` })).toBe("1")
		t.expect(fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", "refs/heads/" }))
			.toBe("refs/heads/main")
	end)

	it("beat pushes a ref from the main checkout too, replaces the older one, and touches no file", function()
		local main = fixture.git(h.f.origin, { "rev-parse", "main" })
		must(zn(h.f.main, { "beat", "c0010" }, T0 + 300), "beat in the main checkout")
		must(zn(h.f.main, { "beat", "c0010" }, T0 + 600), "beat again")
		local list = beats()
		t.expect(#list).toBe(1) -- the older beats of the stamp are deleted
		t.expect(list[1].epoch).toBe(T0 + 600)
		t.expect(fixture.git(h.f.origin, { "rev-parse", "main" })).toBe(main)
		t.expect(fixture.git(h.f.main, { "status", "--porcelain" })).toBe("")
	end)

	it("beat refuses what nobody claims, naming the item and the rule", function()
		for _, id in { "c0020", "c0040", "c9999" } do
			local r = zn(h.f.main, { "beat", id }, T0)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, id)).toBe(true)
		end
		t.expect(has(zn(h.f.main, { "beat", "c0020" }, T0).stderr, "no claim")).toBe(true)
		t.expect(#beats()).toBe(1)
	end)

	it("ready beats for the raft it claims", function()
		must(zn(h.f.main, { "ready", "R0010" }, T0), "ready R0010")
		local stamp = stampOf("R0010", "pickman/.tracker/rafts/active/R0010/R0010.md")
		local found = false
		for _, b in beats() do
			found = found or (b.stamp == stamp and b.epoch == T0)
		end
		t.expect(found).toBe(true)
		t.expect(string.sub(stamp, 1, 7)).toBe("active-")
	end)
end)
