--!strict
-- f0420: a theme at a time and a named ticket, at the command: `./zn work next <tributary>`, `./zn work <tributary>` and
-- `./zn work next <ticket>`. Real git in a small fixture under .cache; no gh is called by `work next`.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local NEW = "new-amber-otter-marble"

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return (string.gsub(r.stderr .. r.stdout, "\r", ""))
end

local function item(id: string, tributary: string, deps: string): string
	local line = if tributary ~= "" then `tributary: {tributary}\n` else ""
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: \ndepends_on: [{deps}]\n{line}emergent: false\ndesign: draft\ncreated: 2026-11-16\nstatus: {NEW}\n---\n\n# {id}\n\n## Problem\nx\n`
end

local f: trackerfix.Fixture = nil :: any

local function setup()
	if f then
		return
	end
	f = trackerfix.new("f0420-theme-cli", {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		[`{ROOT}/tributaries.toml`] = '[[tributary]]\nname = "alpha"\npurpose = "the first theme"\n\n[[tributary]]\nname = "beta"\npurpose = "the second theme"\n',
		[`{ROOT}/issues/c0010/c0010.md`] = item("c0010", "beta", ""),
		[`{ROOT}/issues/c0020/c0020.md`] = item("c0020", "alpha", ""),
		[`{ROOT}/issues/c0030/c0030.md`] = item("c0030", "alpha", "c0010"),
		-- unsorted, and the most unblocking unit of all: what an unfiltered pick takes
		[`{ROOT}/issues/c0050/c0050.md`] = item("c0050", "", ""),
		[`{ROOT}/issues/c0060/c0060.md`] = item("c0060", "", "c0050"),
		[`{ROOT}/issues/c0070/c0070.md`] = item("c0070", "", "c0050"),
	})
end

local function zn(args: { string }): fixture.Result
	return trackerfix.tr(f, f.main, args, nil)
end

return t.spec("f0420: a theme at a time, at the command", function(it)
	it("a theme takes what its tickets depend on, from the bottom, wherever it lives", function()
		setup()
		local out = say(zn({ "work", "next", "alpha" }))
		t.expect(has(out, "c0010: draft - ")).toBe(true)
		t.expect(has(out, "c0050")).toBe(false) -- the unfiltered pick, which this theme must not take
	end)

	it("a theme leaves another theme's unrelated tickets alone", function()
		setup()
		local unsorted = say(zn({ "work", "next", "unsorted" }))
		t.expect(has(unsorted, "c0050: draft - ")).toBe(true)
		t.expect(has(unsorted, "c0010")).toBe(false)
		-- beta's own unit is c0010, which alpha's c0030 needs: the unsorted c0050 that unblocks more is not its
		local beta = say(zn({ "work", "next", "beta" }))
		t.expect(has(beta, "c0010: draft - ")).toBe(true)
		t.expect(has(beta, "c0050")).toBe(false)
	end)

	it("an unknown tributary is refused, naming the valid ones", function()
		setup()
		local r = zn({ "work", "next", "gamma" })
		t.expect(r.ok).toBe(false)
		local out = say(r)
		t.expect(has(out, "gamma is not a raft, a ticket or a tributary here")).toBe(true)
		t.expect(has(out, "tributaries: alpha, beta, unsorted")).toBe(true)
		local earlierRun = zn({ "work", "next", "earlier-work" })
		t.expect(earlierRun.ok).toBe(false)
		t.expect(has(say(earlierRun), "earlier-work holds only finished units")).toBe(true)
		local plain = zn({ "work", "gamma" })
		t.expect(plain.ok).toBe(false)
		t.expect(has(say(plain), "tributaries: alpha, beta, unsorted")).toBe(true)
	end)

	it("work <tributary> prints the skill and names the theme to pass on", function()
		setup()
		local r = zn({ "work", "alpha" })
		t.expect(r.ok).toBe(true)
		t.expect(has(say(r), "This session's theme is the tributary alpha")).toBe(true)
	end)

	it("a theme and --one do not go together", function()
		setup()
		t.expect(zn({ "work", "next", "--one", "alpha" }).ok).toBe(false)
	end)

	it("without a theme the pick is as before: what unblocks the most", function()
		setup()
		t.expect(has(say(zn({ "work", "next" })), "c0050: draft - ")).toBe(true)
	end)
end)
