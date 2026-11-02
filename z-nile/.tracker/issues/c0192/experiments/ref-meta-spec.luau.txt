--!strict
-- c0192: the enforcing ref of the lesson zz-review/bound-every-probe (c0181: a lesson points at the check that holds
-- its rule). It holds in the gate what the lesson says: the hook's logic refuses a bare probe and names the wrapper,
-- lets the wrapped one through, AGENTS.md still carries the rule sentence, the lesson repeats it word for word, and
-- every path the lesson's Enforced by line names exists. Run from z-nile/, as every spec in tests/ is.
local boundcmd = require("@znile/engine/boundcmd")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local LESSON = "z-nile/skills/zz-review/lessons/bound-every-probe.md"

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- the sentence from "Run every probe" to the first "when you do." after it, or nil when AGENTS.md has none
local function sentence(agents: string): string?
	local from = string.find(agents, "Run every probe", 1, true)
	if not from then
		return nil
	end
	local _, to = string.find(agents, "when you do.", from, true)
	return if to then string.sub(agents, from, to) else nil
end

return t.spec("zz-review/bound-every-probe", function(it)
	it(
		"[zz-review/bound-every-probe] a bare probe is refused and the wrapped one passes, and the lesson carries the AGENTS.md rule and names files that exist",
		function()
			local bare = boundcmd.check("lune run probe.luau")
			t.expect(bare.ok).toBe(false)
			t.expect(has(bare.say or "", "./zn run --time")).toBe(true)
			t.expect(boundcmd.check("./zn run --time 60 -- lune run probe.luau").ok).toBe(true)

			local rule = sentence(read("AGENTS.md"))
			t.expect(rule ~= nil).toBe(true) -- AGENTS.md without the rule is a failure, never a pass
			local lesson = read(LESSON)
			t.expect(has(lesson, rule :: string)).toBe(true)

			local line = string.match(lesson, "\n(%*%*Enforced by%*%*[^\n]*)") or ""
			local named = 0
			for path in string.gmatch(line, "`([^`]+)`") do
				if has(path, "/") or string.match(path, "%.md$") then
					named += 1
					t.expect(`{path} {fs.isFile(`{TOP}/{path}`)}`).toBe(`{path} true`)
				end
			end
			t.expect(named >= 5).toBe(true)
		end
	)
end)
