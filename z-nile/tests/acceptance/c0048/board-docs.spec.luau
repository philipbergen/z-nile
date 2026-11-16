--!strict
-- c0460: the tracker skill says where the published board is and how to fetch it.
local fs = require("@lune/fs")
-- c0120 override: the spec runs from its project's home after the move
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from z-nile/; the skill is read from the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0460 board docs", function(it)
	it("the tracker skill's board row names the local board command", function()
		-- c0120 override: the spec runs from its home: the checkout's files are read from the top
		-- c0172 override: the artifact tokens left with the board workflow. The row still names the local command.
		local text = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
		local row = ""
		for line in string.gmatch(text, "[^\n]+") do
			if string.sub(line, 1, 10) == "| board | " then
				row = line
			end
		end
		t.expect(row ~= "").toBe(true)
		t.expect(string.find(row, "./zn board", 1, true) ~= nil).toBe(true)
	end)
end)
