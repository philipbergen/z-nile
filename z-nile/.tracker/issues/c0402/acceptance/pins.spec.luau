--!strict
-- c0402 AC3: the promoted c0116 specs (plan.spec the constant, docs.spec the z-raft sentence) pin 3,000. Reads the real tree as text with plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0402 the promoted c0116 specs pin 3,000", function(it)
	it("the promoted c0116 specs pin 3,000: plan.spec the constant, docs.spec the z-raft sentence", function()
		local plan = read("z-nile/tests/acceptance/c0116/plan.spec.luau")
		t.expect(has(plan, "t.expect(raftplan.CAP).toBe(3000)")).toBe(true)
		t.expect(has(plan, "size cap of 3,000 changed lines")).toBe(true)
		t.expect(has(plan, "size cap of 1,500")).toBe(false)
		local docs = read("z-nile/tests/acceptance/c0116/docs.spec.luau")
		t.expect(has(docs, "a raft that would pass about 3,000 changed lines")).toBe(true)
		t.expect(has(docs, "about 1,500")).toBe(false)
	end)
end)
