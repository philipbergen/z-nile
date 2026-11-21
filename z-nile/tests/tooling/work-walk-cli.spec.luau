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
local env: { [string]: string } = {}
local GH_LOG = ""

local function setup()
	if f then
		return
	end
	local raft =
		`---\nid: R0100\ntype: chore\ntitle: R0100 raft\nslug: R0100\nsingle: false\nissues: [c0101]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# R0100\n\n## Order & dependencies\nc0101\n`
	local CLAIM = "preparing-quiet-copper-falcon"
	local fx = trackerfix.new("f0420-walk-cli", {
		[`{ROOT}/rafts/R0120/R0120.md`] = `---\nid: R0120\ntype: chore\ntitle: R0120 raft\nslug: R0120\nsingle: false\nissues: [c0121]\ndesign: ready\ncreated: 2026-11-16\nstatus: {CLAIM}\n---\n\n# R0120\n\n## Order & dependencies\nc0121\n`,
		[`{ROOT}/issues/c0121/c0121.md`] = item("c0121", "R0120", "", PREPARED, "ready"),
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		[`{ROOT}/rafts/R0100/R0100.md`] = raft,
		[`{ROOT}/issues/c0101/c0101.md`] = item("c0101", "R0100", "c0090", PREPARED, "ready"),
		[`{ROOT}/issues/c0090/c0090.md`] = item("c0090", "", "", NEW, "draft"),
	})
	f = fx
	-- this checkout remembers the claim on R0120, and `gh` is a stub that logs its calls
	fs.writeDir(`{fx.main}/.cache`)
	fs.writeFile(`{fx.main}/.cache/tracker-claim-R0120`, CLAIM)
	local bin = `{fx.base}/bin`
	GH_LOG = `{fx.base}/gh.log`
	fs.writeDir(bin)
	fs.writeFile(
		`{bin}/gh`,
		'#!/bin/sh\necho "$*" >> "' .. GH_LOG .. '"\necho \'[{"number":7,"state":"MERGED"}]\'\n'
	)
	process.exec("chmod", { "+x", `{bin}/gh` })
	env = { PATH = `{bin}:{process.env.PATH or ""}` }
end

local function next(args: { string }, env2: { [string]: string }?): string
	local argv = { "work", "next" }
	for _, a in args do
		table.insert(argv, a)
	end
	local merged = table.clone(env)
	for k, v in (env2 or {}) :: { [string]: string } do
		merged[k] = v
	end
	return say(trackerfix.tr(f, f.main, argv, merged))
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

	it(
		"N3: only a named walk looks up a remembered claim (and its pull request); unnamed and --one do not",
		function()
			setup()
			local function calls(): string
				return if fs.isFile(GH_LOG) then fs.readFile(GH_LOG) else ""
			end
			next({})
			next({ "--one", "R0120" })
			next({ "R0120" }, { ZN_DISPATCH = "1" })
			t.expect(calls()).toBe("")
			local out = next({ "R0120" })
			t.expect(
				has(
					out,
					"R0120: rafting - R0120 is being rafted and this checkout's claim is in the main checkout."
				)
			).toBe(true)
			t.expect(has(out, "Its pull request #7 already merged without giving the claim back.")).toBe(true)
			t.expect(has(out, "run ./zn release R0120 (it is this checkout's own claim, so no --force)"))
				.toBe(true)
			t.expect(has(calls(), "pr list --state all --head main --json number,state --limit 5")).toBe(true)
		end
	)
end)
