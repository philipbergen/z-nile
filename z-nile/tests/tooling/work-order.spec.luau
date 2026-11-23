--!strict
-- f0420 step 9 (AC18): an unnamed `work next` takes the unit that unblocks the most, then the lowest id; one function
-- (`work.order`) holds the rule. Pure: facts in, one Decision out.
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

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

local function layer(position: number, id: string, finished: boolean): work.LayerFact
	return {
		position = position,
		issue = id,
		name = `x/{position}/{id}`,
		commits = 2,
		onlyStart = false,
		finished = finished,
	}
end

-- A raft built, reviewed and traced, whose members await the person (every layer finished).
local function awaiting(id: string, member: string): work.RaftFact
	return raft(id, {
		where = "active",
		issues = { member },
		layers = { layer(1, member, true) },
		stacked = true,
		codeReview = "resolved",
		finalReview = "approved",
		trace = true,
		traceOk = true,
		lands = true,
		unapproved = { `{member} (no approval)` },
	})
end

local AUTHOR = "Ada <ada@example>"

-- R0020 (member c0020) has R0030 and R0040 waiting on it; R0010 (member c0010) has nobody waiting.
local function chain(): ({ work.RaftFact }, { work.IssueFact })
	return {
		raft("R0010", { issues = { "c0010" } }),
		raft("R0020", { issues = { "c0020" } }),
		raft("R0030", { issues = { "c0030" }, outside = { "c0020" }, depsMet = false }),
		raft("R0040", { issues = { "c0040" }, outside = { "c0020" }, depsMet = false }),
	}, {
		prepared("c0010", { raft = "R0010" }),
		prepared("c0020", { raft = "R0020" }),
		prepared("c0030", { raft = "R0030", deps = { "c0020" } }),
		prepared("c0040", { raft = "R0040", deps = { "c0020" } }),
	}
end

return t.spec("f0420 step 9: unnamed work is ordered by what it unblocks", function(it)
	it("AC18: the claimable raft with the most dependents is taken before a lower id", function()
		local rafts, issues = chain()
		local d = work.decide({ rafts = rafts, issues = issues })
		t.expect(d.action).toBe("ready")
		t.expect(d.raft).toBe("R0020")
	end)

	it("AC18: with no dependents the lower id is taken, as today", function()
		local d = work.decide({
			rafts = { raft("R0020", { issues = { "c0020" } }), raft("R0010", { issues = { "c0010" } }) },
			issues = { prepared("c0010", { raft = "R0010" }), prepared("c0020", { raft = "R0020" }) },
		})
		t.expect(d.raft).toBe("R0010")
	end)

	it("AC18: equal counts fall back to the id", function()
		local d = work.decide({
			rafts = {
				raft("R0020", { issues = { "c0020" } }),
				raft("R0010", { issues = { "c0010" } }),
				raft("R0030", { issues = { "c0030" }, outside = { "c0010", "c0020" }, depsMet = false }),
			},
			issues = {
				prepared("c0010", { raft = "R0010" }),
				prepared("c0020", { raft = "R0020" }),
				prepared("c0030", { raft = "R0030", deps = { "c0010", "c0020" } }),
			},
		})
		t.expect(d.raft).toBe("R0010")
	end)

	it("AC18: the ticket to design that unblocks the most is designed first", function()
		local d = work.decide({
			rafts = {},
			issues = {
				issue("c0010"),
				issue("c0020"),
				issue("c0030", { deps = { "c0020" } }),
			},
		})
		t.expect(d.action).toBe("draft")
		t.expect(d.ticket).toBe("c0020")
	end)

	it("AC18: the ticket to raft that unblocks the most is rafted first", function()
		local d = work.decide({
			rafts = {},
			issues = {
				prepared("c0010"),
				prepared("c0020"),
				issue("c0030", { deps = { "c0020" } }),
			},
		})
		t.expect(d.action).toBe("rafting")
		t.expect(d.ticket).toBe("c0020")
	end)

	it("AC18: a unit another worker holds still counts its dependents' wait", function()
		local rafts, issues = chain()
		-- R0030 and R0040 are held by other workers: they are not candidates, but R0020 still unblocks them
		local d = work.decide({ rafts = rafts, issues = issues, claims = { R0030 = "w1", R0040 = "w2" } })
		t.expect(d.raft).toBe("R0020")
	end)

	it("AC18: work further along is resumed before a new unit that unblocks more", function()
		local rafts, issues = chain()
		table.insert(
			rafts,
			raft("R0005", {
				where = "active",
				status = "active",
				holder = AUTHOR,
				issues = { "c0005" },
				layers = { layer(1, "c0005", false) },
			})
		)
		table.insert(issues, prepared("c0005", { raft = "R0005" }))
		local d =
			work.decide({ rafts = rafts, issues = issues, author = AUTHOR, session = "s1", carriers = {} })
		t.expect(d.raft).toBe("R0005")
		t.expect(d.action).toBe("finish")
	end)

	it("AC18: of two held rafts to resume the one that unblocks more comes first", function()
		local function built(id: string, member: string): work.RaftFact
			return raft(id, {
				where = "active",
				status = "active",
				holder = AUTHOR,
				issues = { member },
				layers = { layer(1, member, false) },
			})
		end
		local d = work.decide({
			author = AUTHOR,
			session = "s1",
			carriers = {},
			rafts = {
				built("R0010", "c0010"),
				built("R0020", "c0020"),
				raft("R0030", { issues = { "c0030" }, outside = { "c0020" }, depsMet = false }),
			},
			issues = {
				prepared("c0010", { raft = "R0010" }),
				prepared("c0020", { raft = "R0020" }),
				prepared("c0030", { raft = "R0030", deps = { "c0020" } }),
			},
		})
		t.expect(d.raft).toBe("R0020")
	end)

	it("work.order is the one function: most unblocks, then id; rankKey is gone", function()
		local rafts, issues = chain()
		local order = (work :: any).order
		t.expect(type(order)).toBe("function")
		local got = order({ "R0010", "R0020", "R0030" }, { rafts = rafts, issues = issues })
		t.expect(table.concat(got, ",")).toBe("R0020,R0010,R0030")
		t.expect((work :: any).rankKey).toBe(nil)
	end)
end)
