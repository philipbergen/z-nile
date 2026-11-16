--!strict
-- c0253 AC10: the board shows the live supervisor on the card of the item it holds (the card's dispatch row: step
-- "worker", its state, its CLI), and shows nothing for a stopped supervisor, a dead one or a state file it cannot read.
-- Fixture folders under .cache/c0253-board; no process is started beyond `kill -0` on a pid.
local board = require("@znile/engine/board")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local supervise = require("@znile/engine/supervise")
local t = require("@tests/lib/t")

local BASE = (fixture.physical(".") :: string) .. "/.cache/c0253-board"

local function dirWith(name: string, state: string?): string
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(`{dir}/.cache/work`)
	if state then
		fs.writeFile(`{dir}/.cache/work/state`, state)
	end
	return dir
end

local function stateOf(pid: number, state: string): string
	return supervise.stateText({
		pid = pid,
		state = state,
		item = "R0010",
		cli = "claude",
		since = "t",
		moved = 0,
		blocked = 0,
		held = "R0010",
	})
end

-- this spec's own runner process: alive for as long as the spec runs
local ALIVE = tonumber((string.gsub(process.exec("sh", { "-c", "echo $PPID" }).stdout, "%s+", ""))) or 1

return t.spec("c0253 the board shows the supervisor", function(it)
	it("AC10: a live supervisor is the dispatch row of the item it holds", function()
		local facts = board.readFacts(dirWith("live", stateOf(ALIVE, "working")))
		local row = facts.dispatch.R0010
		t.expect(row ~= nil).toBe(true)
		t.expect(row.step).toBe("worker")
		t.expect(row.outcome).toBe("working")
		t.expect(row.model).toBe("claude")
	end)

	it("AC10: a stopped, a dead and an unreadable supervisor show nothing", function()
		t.expect(board.readFacts(dirWith("stopped", stateOf(ALIVE, "stopped"))).dispatch.R0010).toBe(nil)
		t.expect(board.readFacts(dirWith("dead", stateOf(99999999, "working"))).dispatch.R0010).toBe(nil)
		t.expect(board.readFacts(dirWith("junk", "pid: soon\n")).dispatch.R0010).toBe(nil)
		t.expect(board.readFacts(dirWith("none", nil)).dispatch.R0010).toBe(nil)
	end)

	it("AC10: the dispatcher's own row for the item wins", function()
		local dir = dirWith("both", stateOf(ALIVE, "working"))
		fs.writeDir(`{dir}/.cache/dispatch/R0010`)
		fs.writeFile(
			`{dir}/.cache/dispatch/R0010/state.json`,
			'{"step":"z-run","outcome":"ok","model":"grok-4.7"}'
		)
		local row = board.readFacts(dir).dispatch.R0010
		t.expect(row.step).toBe("z-run")
	end)
end)
