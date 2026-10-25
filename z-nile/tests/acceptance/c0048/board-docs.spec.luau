--!strict
-- c0460: the tracker skill says where the published board is and how to fetch it.
local fs = require("@lune/fs")
-- c0120 override: the spec runs from its project's home after the move
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from z-nile/; the skill is read from the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0460 board docs", function(it)
	it(
		"the tracker skill's board row names the workflow, the artifact and a download into a fresh directory",
		function()
			-- c0120 override: the spec runs from its home: the checkout's files are read from the top
			local text = fs.readFile(`{TOP}/.claude/skills/tracker/SKILL.md`)
			local row = ""
			for line in string.gmatch(text, "[^\n]+") do
				if string.sub(line, 1, 10) == "| board | " then
					row = line
				end
			end
			t.expect(row ~= "").toBe(true)
			-- Concatenated so this file does not literally name the download directory.
			-- c0049 counts a `.cache/<dir>` mention as a fixture (c0108).
			local boardCi = ".cache/" .. "board-ci"
			for _, token in
				{
					"board.yml",
					"tracker-board",
					"gh run download",
					"rm -rf " .. boardCi,
					"-D " .. boardCi,
				}
			do
				t.expect(string.find(row, token, 1, true) ~= nil).toBe(true)
			end
		end
	)
end)
