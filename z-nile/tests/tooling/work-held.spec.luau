--!strict
-- f0420 step 4b review fixes (pure): units other workers hold stay in the facts and are not candidates (F1); a named walk
-- whose units are held answers a plain wait that names the holders, never the Stops text (F2); a held wait does not erase
-- the holder's carriers row (F5); the worker's identity from an injected process chain (F7); a quiet worker is never "lost"
-- and a held unit names its release (F3, F4).
local fs = require("@lune/fs")
local liveview = require("@znile/engine/liveview")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")
local workerlive = require("@znile/engine/workerlive")
local workread = require("@znile/engine/workread")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function raft(id: string, over: { [string]: any }?): work.RaftFact
	local r: work.RaftFact = {
		id = id,
		title = id,
		where = "backlog",
		status = "prepared",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = {},
		layers = {},
		holder = "",
		since = "",
		stacked = false,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
		root = "z-nile/.tracker",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

local function issue(id: string, over: { [string]: any }?): work.IssueFact
	local i: work.IssueFact = {
		id = id,
		root = "z-nile/.tracker",
		status = "new",
		raft = "",
		designReady = false,
		sized = false,
		deps = {},
		draftBlock = "",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function prepared(id: string, over: { [string]: any }?): work.IssueFact
	local i = issue(id, { status = "prepared", designReady = true, sized = true })
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local STOPS = "is not landed yet:"

return t.spec("f0420 step 4b: held units, identity and quiet workers", function(it)
	it(
		"F1 an unnamed pick skips a held unit as a candidate but its dependent still sees it as not landed",
		function()
			local issues = { issue("c0090"), issue("c0091", { deps = { "c0090" } }) }
			local free = work.decide({ rafts = {}, issues = issues, session = "s" })
			t.expect(free.ticket).toBe("c0090")
			local held =
				work.decide({ rafts = {}, issues = issues, session = "s", claims = { c0090 = "w1" } })
			-- the held dependency is still a fact: c0091 is not handed out as if c0090 had landed (a deleted fact reads so)
			t.expect(held.ticket ~= "c0090").toBe(true)
			t.expect(held.ticket ~= "c0091" or has(held.why, "depends on c0090")).toBe(true)
			t.expect(held.action ~= "ready" and held.action ~= "rafting").toBe(true)
		end
	)

	it("F1 a prepared light dependent of a held unit is not told to ready", function()
		local issues = {
			issue("c0090"),
			prepared("c0091", { deps = { "c0090" }, level = "easy", light = true }),
		}
		local held = work.decide({ rafts = {}, issues = issues, session = "s", claims = { c0090 = "w1" } })
		t.expect(held.action ~= "ready").toBe(true)
		t.expect(held.ticket ~= "c0090").toBe(true) -- the held unit is not offered either
	end)

	it(
		"F2 a named raft held by another worker is a plain wait naming the holder, with nothing owed",
		function()
			local r = raft("R0100", { issues = { "c0100" } })
			local d = work.decide({
				asked = "R0100",
				rafts = { r },
				issues = { prepared("c0100", { raft = "R0100" }) },
				claims = { R0100 = "claude-7@h" },
			})
			t.expect(d.action).toBe("wait")
			t.expect(d.owed).toBe(nil)
			t.expect(has(d.why, "R0100 is held by claude-7@h")).toBe(true)
			t.expect(has(d.why, STOPS)).toBe(false)
		end
	)

	it("F2 a named raft whose dependency raft is held waits the same way, naming that holder", function()
		local dep = raft("R0090", { issues = { "c0090" } })
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090" }, depsMet = false })
		local d = work.decide({
			asked = "R0100",
			rafts = { top, dep },
			issues = {
				prepared("c0090", { raft = "R0090" }),
				prepared("c0100", { raft = "R0100", deps = { "c0090" } }),
			},
			claims = { R0090 = "grok-3@h" },
		})
		t.expect(d.action).toBe("wait")
		t.expect(d.owed).toBe(nil)
		t.expect(has(d.why, "R0090 is held by grok-3@h")).toBe(true)
		t.expect(has(d.why, STOPS)).toBe(false)
	end)

	it("F5 a held wait erases only this session's own carriers row", function()
		local dir = `{process.cwd}/.cache/f0420-carry`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		workread.carry(dir, "R0100", "sessionA")
		workread.carry(dir, "R0100", nil, "sessionB") -- B was told to wait: A's row stays
		t.expect(workread.carriers(dir).R0100.session).toBe("sessionA")
		workread.carry(dir, "R0100", nil, "sessionA") -- A lets go: its row goes
		t.expect(workread.carriers(dir).R0100).toBe(nil)
		fs.removeDir(dir)
	end)

	it("F7 the worker's pid is the CLI's process, never the zn process itself", function()
		local chain = {
			{ pid = 50, name = "lune" },
			{ pid = 49, name = "/bin/bash" },
			{ pid = 48, name = "-zsh" },
			{ pid = 47, name = "/usr/local/bin/claude" },
			{ pid = 40, name = "tmux: server" },
		}
		local me = workerlive.identify({ ZN_CLI = "claude", ZN_ACCOUNT = "work-2" }, chain)
		t.expect(me ~= nil).toBe(true)
		t.expect((me :: any).pid).toBe(47)
		t.expect((me :: any).account).toBe("work-2")
		-- the first process that is no shell stands for a CLI no process is named after
		local node = workerlive.identify({ ZN_CLI = "grok" }, {
			{ pid = 50, name = "lune" },
			{ pid = 49, name = "bash" },
			{ pid = 48, name = "node" },
			{ pid = 40, name = "tmux" },
		})
		t.expect((node :: any).pid).toBe(48)
		-- an explicit pid is the owner's word, per terminal
		t.expect((workerlive.identify({ ZN_CLI = "claude", ZN_WORKER_PID = "123" }, chain) :: any).pid)
			.toBe(123)
	end)

	it(
		"F7 a fallback pid that is a multiplexer, terminal or login is no worker, and the hint names ZN_WORKER_PID",
		function()
			for _, name in
				{ "tmux: server", "screen", "login", "sshd", "Terminal", "iTerm2", "zellij", "ghostty" }
			do
				local me, hint = workerlive.identify({ ZN_CLI = "grok" }, {
					{ pid = 50, name = "lune" },
					{ pid = 49, name = "zsh" },
					{ pid = 40, name = name },
				})
				t.expect(me).toBe(nil)
				t.expect(has(hint, "ZN_WORKER_PID")).toBe(true)
			end
		end
	)

	it("F7 a nested CLI under ./zn dispatch is not a worker of its own, and says nothing", function()
		local me, hint = workerlive.identify(
			{ ZN_CLI = "claude", ZN_DISPATCH = "1", ZN_WORKER_PID = "123" },
			{}
		)
		t.expect(me).toBe(nil)
		t.expect(hint).toBe(nil)
	end)

	it("F7 no CLI named is no worker; a label that does not fit is dropped with one hint", function()
		t.expect((workerlive.identify({}, { { pid = 47, name = "claude" } }))).toBe(nil)
		local me, hint = workerlive.identify(
			{ ZN_CLI = "claude", ZN_ACCOUNT = "bad label" },
			{ { pid = 47, name = "claude" } }
		)
		t.expect((me :: any).account).toBe(nil)
		t.expect(has(hint, "ZN_ACCOUNT")).toBe(true)
	end)

	it(
		"F3 a worker the daemon calls lost that holds a claim is shown working and quiet, never lost",
		function()
			local live = liveview.slim({
				ok = true,
				at = 1795262040,
				workers = {
					{
						id = "kimi-3@h",
						cli = "kimi",
						state = "lost",
						heard = 1795100000,
						lost_since = 1795261000,
						can = {},
					},
				},
				claims = { { unit = "c0001", activity = "code", worker = "kimi-3@h", since = 1795100000 } },
			}) :: liveview.Live
			local line = liveview.workerLines(live)[1]
			t.expect(has(line, "working, quiet since 03:36 PST")).toBe(true)
			t.expect(has(line, "lost")).toBe(false)
		end
	)

	it(
		"F4 a held unit is listed with its holder, and a quiet holder's unit names the manual release",
		function()
			local live = liveview.slim({
				ok = true,
				at = 1795262040,
				workers = {
					{
						id = "kimi-3@h",
						cli = "kimi",
						state = "lost",
						heard = 1795100000,
						lost_since = 1795261000,
						can = {},
					},
					{ id = "grok-4@h", cli = "grok", state = "working", heard = 1795262000, can = {} } :: any,
				},
				claims = {
					{ unit = "c0001", activity = "code", worker = "kimi-3@h", since = 1795100000 },
					{ unit = "R0002", activity = "ready", worker = "grok-4@h", since = 1795262000 },
				},
			}) :: liveview.Live
			local all = table.concat(liveview.heldLines(live, nil, false), "\n")
			t.expect(has(all, "c0001 is held by kimi-3@h")).toBe(true)
			t.expect(has(all, "./zn live release --worker kimi-3@h")).toBe(true)
			t.expect(has(all, "R0002 is held by grok-4@h")).toBe(true)
			t.expect(has(all, "./zn live release --worker grok-4@h")).toBe(false)
			local quiet = table.concat(liveview.heldLines(live, nil, true), "\n")
			t.expect(has(quiet, "R0002")).toBe(false)
			local mine = table.concat(liveview.heldLines(live, "grok-4@h", false), "\n")
			t.expect(has(mine, "R0002")).toBe(false)
		end
	)

	it("a Stops text with something owed and a held unit also names the holder", function()
		local dep = raft("R0090", { issues = { "c0080" } })
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090", "c0080" }, depsMet = false })
		local d = work.decide({
			asked = "R0100",
			rafts = { top, dep },
			issues = {
				prepared("c0080", { raft = "R0090" }),
				issue("c0090", { draftBlock = "no idea-review-001.md" }),
				prepared("c0100", { raft = "R0100", deps = { "c0090", "c0080" } }),
			},
			claims = { R0090 = "grok-3@h" },
		})
		t.expect(d.owed ~= nil).toBe(true) -- the person still owes the idea review: the Stops text stands
		t.expect(has(d.why, "R0090 is held by grok-3@h")).toBe(true)
	end)
end)
