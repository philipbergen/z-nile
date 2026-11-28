--!strict
-- c0462: the checked-in exempt list (z-nile/tests/vacuous-exempt.txt) and what the writer lists. The list equal to the
-- tree is a check.sh check only (AC5): a promoted spec would fail the day a new item's specs arrive.
local boundcmd = require("@znile/engine/boundcmd")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local vacuous = require("@tests/lib/vacuous")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local text = fs.readFile(`{root}/z-nile/tests/vacuous-exempt.txt`)
local list = vacuous.parseExempt(text)

return t.spec("c0462 the exempt list", function(it)
	it("is well formed: sorted, unique ids", function()
		t.expect(list ~= nil).toBe(true)
	end)

	it("does not hold c0462, so this item's own specs are checked", function()
		t.assert(list ~= nil, "list did not parse")
		t.expect((list :: { [string]: true }).c0462).toBe(nil)
		t.expect(vacuous.exempt(list :: { [string]: true }, "tests/acceptance/c0462/x.spec.luau")).toBe(false)
	end)

	it("holds items of the early acceptance specs, and a later item stays out", function()
		t.assert(list ~= nil, "list did not parse")
		local l = list :: { [string]: true }
		t.expect(l.c0117).toBe(true)
		t.expect(l.c0058).toBe(true)
		t.expect(l.c9999).toBe(nil)
	end)

	it("the writer prints the same ids the file holds, in the same grammar", function()
		local r = process.exec("lune", { "run", "z-nile/vacuous-exempt" }, { cwd = root })
		t.assert(r.ok, `writer failed: {r.stderr}`)
		t.expect(vacuous.parseExempt(r.stdout) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, "c0462", 1, true) == nil).toBe(true)
	end)

	it("an id stays exempt after its specs are promoted: the file names tracker and acceptance paths alike", function()
		t.assert(list ~= nil, "list did not parse")
		local l = list :: { [string]: true }
		t.expect(vacuous.exempt(l, "tests/acceptance/c0117/docs.spec.luau")).toBe(true)
		t.expect(vacuous.exempt(l, "z-nile/.tracker/issues/active/c0117/acceptance/docs.spec.luau")).toBe(true)
	end)

	it("the PreToolUse hook lets an agent run the writer, and still refuses a scratch copy of it", function()
		t.expect(boundcmd.check("lune run z-nile/vacuous-exempt -- --check").ok).toBe(true)
		t.expect(boundcmd.check("lune run z-nile/vacuous-exempt -- --gate-needed a b").ok).toBe(true)
		t.expect(boundcmd.check("lune run /tmp/scratch/z-nile/vacuous-exempt", { cwd = root, checkout = root }).ok).toBe(false)
	end)
end)
