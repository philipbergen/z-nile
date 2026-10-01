--!strict
-- c0460: the tracker skill says where the published board is and how to fetch it.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

return t.spec("c0460 board docs", function(it)
	it("the tracker skill's board row names the workflow, the artifact and the download command", function()
		local text = fs.readFile(".claude/skills/tracker/SKILL.md")
		local row = ""
		for line in string.gmatch(text, "[^\n]+") do
			if string.sub(line, 1, 10) == "| board | " then
				row = line
			end
		end
		t.expect(row ~= "").toBe(true)
		for _, token in { "board.yml", "tracker-board", "gh run download" } do
			t.expect(string.find(row, token, 1, true) ~= nil).toBe(true)
		end
	end)
end)
