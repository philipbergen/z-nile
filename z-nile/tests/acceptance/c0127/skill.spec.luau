--!strict
-- c0127 AC3: the testing skill restates the lock's takeover rule, so it moves with the code.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0127 the testing skill's lock rule", function(it)
	it(
		"the testing skill's Lock rule says a reused pid (its start id differs) does not hold, and an unreadable one does",
		function()
			local skill = fs.readFile(`{root}/.claude/skills/testing/SKILL.md`)
			local line = string.match(skill, "\n%s*%- %*%*Lock%*%*:[^\n]*") or ""
			t.expect({
				reused = has(line, "differs from the one recorded"),
				unknown = has(line, "can't be read still holds"),
			}).toEqual({
				reused = true,
				unknown = true,
			})
		end
	)
end)
