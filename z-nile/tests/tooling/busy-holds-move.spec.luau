--!strict
-- c0120's freeze (`./zn busy <paths>`) ignores a branch whose history holds c0120's move, the commit its approving
-- review pins as `Move commit: <sha>` (decided with the coordinator, 2026-10-24: once #99 merged c0120's prep into main,
-- "stacked on its prep" could no longer tell a stacked branch apart). A branch that only looks like one is listed, and
-- so is a stacked one when no approved review pins a move. Fixture under .cache/busy-holds-move (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local MARK = "tracker/rafts/done/R0001/check.sh"
local OLD = { "tracker", "src", "tests" }
local REVIEW = "z-nile/.tracker/issues/active/c0120/review-012.md"
local f: trackerfix.Fixture

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function branchOff(name: string, from: string, file: string): string
	fixture.git(f.main, { "checkout", "-q", "-b", name, from })
	fs.writeFile(`{f.main}/{file}`, `--!strict\nreturn "{name}"\n`)
	fixture.git(f.main, { "add", "-A" })
	fixture.git(f.main, { "commit", "-qm", name })
	local sha = (string.gsub(fixture.git(f.main, { "rev-parse", "HEAD" }), "%s+$", ""))
	fixture.git(f.main, { "checkout", "-q", "main" })
	return sha
end
local function review(text: string)
	fs.writeDir(`{f.main}/z-nile/.tracker/issues/active/c0120`)
	fs.writeFile(`{f.main}/{REVIEW}`, text)
end

return t.spec("c0120's freeze ignores a branch that holds c0120's pinned move", function(it)
	it("ignores a branch holding the pinned move, and lists a look-alike or an unpinned one", function()
		local seed: { [string]: string } = {
			["z-nile/projects.toml"] = REGISTRY,
			["src/a.luau"] = "--!strict\nreturn 1\n",
			[MARK] = "#!/usr/bin/env bash\n",
		}
		for _, state in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			seed[`pickman/.tracker/{state}/.gitkeep`] = ""
		end
		f = trackerfix.new("busy-holds-move", seed)
		-- c0120's implementation: its move, then a branch built on it
		local move = branchOff("impl-move", "main", "src/moved.luau")
		branchOff("stacked-on-move", "impl-move", "src/stacked.luau")
		branchOff("impl-c0199", "main", "src/lookalike.luau")
		-- the current branch is impl-move, as c0120's own branch runs AC16
		fixture.git(f.main, { "checkout", "-q", "impl-move" })
		review(
			`# Review\nPrep reference: {move}\nMove commit: {move}\nCore commit: {move}\n\nVerdict: approve\n`
		)
		local r = trackerfix.tr(f, f.main, { "busy", table.unpack(OLD) })
		t.expect(has(r.stdout, "stacked-on-move")).toBe(false)
		t.expect(has(r.stderr, "ignored for c0120's freeze: stacked-on-move (holds its move)")).toBe(true)
		t.expect(has(r.stdout, "branch impl-c0199 changes")).toBe(true)
		t.expect(r.code).toBe(1)
		-- no approved review: nothing is exempt for holding a move
		review(`# Review\nMove commit: {move}\n\nVerdict: changes\n`)
		local u = trackerfix.tr(f, f.main, { "busy", table.unpack(OLD) })
		t.expect(has(u.stdout, "branch stacked-on-move changes")).toBe(true)
		fs.removeFile(`{f.main}/{REVIEW}`)
		fixture.git(f.main, { "checkout", "-q", "main" })
	end)

	it("c0120's own raft, active on origin/main, is ignored; another active raft is listed", function()
		trackerfix.elsewhere(f, {
			["z-nile/.tracker/rafts/active/R0048/R0048.md"] = "---\nid: R0048\nissues: [c0120]\n---\n",
		}, "tracker: ready R0048")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local r = trackerfix.tr(f, f.main, { "busy", table.unpack(OLD) })
		t.expect(has(r.stdout, "raft R0048")).toBe(false)
		t.expect(has(r.stderr, "ignored for c0120's freeze: raft R0048 (c0120's own)")).toBe(true)
		t.expect(r.code).toBe(1) -- impl-c0199 still holds src
		trackerfix.elsewhere(f, {
			["z-nile/.tracker/rafts/active/R0049/R0049.md"] = "---\nid: R0049\nissues: [c0120x, c0121]\n---\n",
		}, "tracker: ready R0049")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local o = trackerfix.tr(f, f.main, { "busy", table.unpack(OLD) })
		t.expect(has(o.stdout, "raft R0049 is active")).toBe(true)
		-- without paths (compaction's set) the freeze is off: c0120's raft is listed too
		t.expect(has(trackerfix.tr(f, f.main, { "busy" }).stdout, "raft R0048 is active")).toBe(true)
	end)
end)
