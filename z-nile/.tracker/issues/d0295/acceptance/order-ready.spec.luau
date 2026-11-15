--!strict
-- d0295 AC2: readycheck.reason, the check `./zn ready` and `./zn work` share, refuses a raft whose Order `./zn start`
-- would refuse in the Order's text (a non-member id, a member named twice, a dependent before its depends_on), also
-- for a caller that has not loaded the design files yet (loaded = false), and accepts the same order written under
-- `## Cross-raft waits`.
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")

local function member(id: string, deps: { string }?): readycheck.Member
	local list: { readycheck.Dep } = {}
	local given: { string } = deps or {}
	for _, d in given do
		table.insert(list, { id = d, state = "member" })
	end
	return {
		id = id,
		design = "ready",
		doc = "",
		deps = list,
		files = {},
		specs = {},
		approval = nil,
		approvalFile = `z-nile/.tracker/issues/{id}/approval.md`,
	}
end

local function raft(
	order: string,
	members: { readycheck.Member },
	loaded: boolean,
	waits: string?
): readycheck.Raft
	local listed: { string } = {}
	for _, m in members do
		table.insert(listed, m.id)
	end
	local doc = `---\ndesign: ready\n---\n\n# R0090\n\n## Theme\nT.\n\n## Order & dependencies\n{order}\n\n`
		.. (if waits then `## Cross-raft waits\n{waits}\n\n` else "")
		.. "## Risks & rollback\n"
	return {
		id = "R0090",
		where = "backlog",
		status = "prepared",
		dir = "z-nile/.tracker/rafts/R0090",
		design = "ready",
		doc = doc,
		grouped = nil,
		questions = false,
		listed = listed,
		members = members,
		files = {},
		loaded = loaded,
	}
end

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local function refuses(r: readycheck.Raft, ...: string)
	local why = readycheck.reason(r)
	for _, needle in { ... } do
		if not has(why, needle) then
			error(`reason lacks {needle}: {why or "nil"}`, 2)
		end
	end
end

return t.spec("d0295 ready and work refuse an Order start would refuse", function(it)
	it("refuses R0090's Order, which names other rafts' issues, loaded or not", function()
		local order = "One member, c0261. R0090 merges before the rafts of c0264 and c0260."
		for _, loaded in { false, true } do
			refuses(
				raft(order, { member("c0261") }, loaded),
				"R0090's Order & dependencies: ",
				"c0264 is in R0090's Order and is not a member",
				"## Cross-raft waits",
				"./zn stack <R-id>"
			)
		end
	end)

	it("refuses a member named twice, the layer branch's spelling among them", function()
		refuses(
			raft("**c0261**, on `R0090/1/c0261`.", { member("c0261") }, false),
			"c0261 is listed twice in R0090's Order"
		)
	end)

	it("refuses a dependent named before its in-raft depends_on", function()
		refuses(
			raft("c0261, then c0262.", { member("c0261", { "c0262" }), member("c0262") }, false),
			"c0261 is listed before c0262, which it depends on"
		)
	end)

	it(
		"accepts the same order with the other rafts' issues under Cross-raft waits, and raft ids in the Order",
		function()
			local why, complete = readycheck.reason(
				raft(
					"One member, c0261. R0062 is unrelated.",
					{ member("c0261") },
					false,
					"R0090 merges before the rafts of c0264 and c0260."
				)
			)
			t.expect(why).toBe(nil)
			t.expect(complete).toBe(false)
		end
	)

	it("accepts an Order that names no item id (the fallback order)", function()
		local why =
			readycheck.reason(raft("By id.", { member("c0262"), member("c0261", { "c0262" }) }, false))
		t.expect(why).toBe(nil)
	end)

	it(
		"leaves a depends_on cycle among members the Order does not name to start (c0067's cyclic raft is readied)",
		function()
			local why = readycheck.reason(
				raft("By id.", { member("c0070", { "c0080" }), member("c0080", { "c0070" }) }, false)
			)
			t.expect(why).toBe(nil)
		end
	)

	it("leaves a held raft's refusal as it was: only a prepared raft is judged", function()
		local held = raft("c0264 first.", { member("c0261") }, false)
		held.where = "active"
		held.status = "active"
		refuses(held, "only a prepared raft is readied")
		t.expect(has(readycheck.reason(held), "Order & dependencies")).toBe(false)
	end)
end)
