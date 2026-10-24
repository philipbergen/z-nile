--!strict
-- c0121 AC5: zz-rules names `./zn board --serve` in the main checkout's command list and describes it in the board
-- row, in the Design's words; the README says it is built; c0118's row words stay.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local SKILL = fs.readFile("z-nile/skills/zz-rules/SKILL.md")
local function boardRow(): string
	local row = ""
	for line in string.gmatch(SKILL, "[^\n]+") do
		if string.sub(line, 1, 10) == "| board | " then
			row = line
		end
	end
	return row
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0121 docs", function(it)
	it("the main checkout's command list names board --serve and what it may do there", function()
		local a = string.find(SKILL, "The complete list of commands that may run there:", 1, true)
		local b = string.find(SKILL, "The tracker enforces part of this", 1, true)
		t.expect(a ~= nil and b ~= nil).toBe(true)
		local list = string.sub(SKILL, a :: number, b :: number)
		t.expect(
			has(
				list,
				"`./zn board --serve [--port N]` (c0121), which only reads, except for the three actions on its page (stop, retry, open), each delegated"
			)
		).toBe(true)
		t.expect(has(list, "it runs only here, where the dispatcher's run state lives")).toBe(true)
	end)

	it("the board row describes the served page, its guards and its three actions", function()
		local row = boardRow()
		for _, phrase in
			{
				"`./zn board --serve [--port N]` (c0121; main checkout only; default port 8417) serves the same page on 127.0.0.1 and prints its URL once, with a session token",
				"the page polls `/api/state` every 5 s",
				"`gh pr list` at most every 30 s, in the background",
				"a launched raft's spend read from its worktree",
				'"checks unavailable" when `gh` fails',
				'says "server is out of date: restart" when the engine changed since start',
				"stop and retry (`./zn dispatch stop|retry <id>`) and open (the PR, else the worktree)",
				"It refuses a foreign Host or Origin, any OPTIONS, a request without the token, an action that is not a JSON POST, and an id the model lacks.",
				"PR and checks are live only on the served board (c0121)",
				"Views Rafts and Issues",
			}
		do
			if not has(row, phrase) then
				error(`the board row lacks: {phrase}`)
			end
		end
	end)

	it("the README says the served board is built", function()
		local text = fs.readFile("z-nile/README.md")
		t.expect(
			has(
				text,
				"`./zn board --serve` (c0121) serves the same page live from the main checkout, with stop, retry and open."
			)
		).toBe(true)
		t.expect(has(text, "c0121, planned")).toBe(false)
	end)
end)
