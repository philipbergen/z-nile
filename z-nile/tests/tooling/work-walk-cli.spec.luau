--!strict
-- f0420 step 1 at the command: `./zn work next <R>` walks a named raft's dependencies, `--one` and ZN_DISPATCH=1 answer
-- the raft's own next action. Real git in a small fixture under .cache; no gh is called by `work next`.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local NEW = "new-amber-otter-marble"

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return (string.gsub(r.stderr .. r.stdout, "\r", ""))
end

local function item(id: string, raft: string, deps: string, status: string, design: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: {raft}\ndepends_on: [{deps}]\nemergent: false\ndesign: {design}\ncreated: 2026-11-16\nstatus: {status}\n---\n\n# {id}\n\n## Problem\nx\n`
end

local f: trackerfix.Fixture = nil :: any

local function setup()
	if f then
		return
	end
	local raft =
		`---\nid: R0100\ntype: chore\ntitle: R0100 raft\nslug: R0100\nsingle: false\nissues: [c0101]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# R0100\n\n## Order & dependencies\nc0101\n`
	f = trackerfix.new("f0420-walk-cli", {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		[`{ROOT}/rafts/R0100/R0100.md`] = raft,
		[`{ROOT}/issues/c0101/c0101.md`] = item("c0101", "R0100", "c0090", PREPARED, "ready"),
		[`{ROOT}/issues/c0090/c0090.md`] = item("c0090", "", "", NEW, "draft"),
	})
end

local function next(args: { string }, env: { [string]: string }?): string
	local argv = { "work", "next" }
	for _, a in args do
		table.insert(argv, a)
	end
	return say(trackerfix.tr(f, f.main, argv, env))
end

return t.spec("f0420: work next <R> at the command", function(it)
	it("a named raft is answered with its dependency's design, for the raft", function()
		setup()
		local out = next({ "R0100" })
		t.expect(has(out, "c0090: draft - For R0100: ")).toBe(true)
	end)

	it("--one answers the raft's own next action", function()
		setup()
		local out = next({ "--one", "R0100" })
		t.expect(has(out, "R0100: none - ")).toBe(true)
		t.expect(has(out, "it must be done first")).toBe(true)
		t.expect(has(out, "For R0100")).toBe(false)
	end)

	it("under ZN_DISPATCH=1 a named raft is always the one answer", function()
		setup()
		local out = next({ "R0100" }, { ZN_DISPATCH = "1" })
		t.expect(has(out, "R0100: none - ")).toBe(true)
		t.expect(has(out, "For R0100")).toBe(false)
	end)

	it("an unnamed call and a named issue are unchanged", function()
		setup()
		local unnamed = next({})
		t.expect(has(unnamed, "c0090: draft - ")).toBe(true)
		t.expect(has(unnamed, "For R0100")).toBe(false)
		local issue = next({ "c0090" })
		t.expect(has(issue, "c0090: draft - ")).toBe(true)
		t.expect(has(issue, "For R0100")).toBe(false)
	end)
end)
