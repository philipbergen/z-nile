--!strict
-- f0399: z-raft's policy puts a ticket in the raft of what it depends on. Pure.
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")

local ROOT = "z-nile/.tracker"

local function cand(id: string, over: { [string]: any }?): raftplan.Issue
	local kind = if string.sub(id, 1, 1) == "f"
		then "feature"
		elseif string.sub(id, 1, 1) == "d" then "defect"
		else "chore"
	local i: raftplan.Issue = {
		id = id,
		type = kind,
		root = ROOT,
		state = "backlog",
		status = "prepared",
		design = "ready",
		raft = "",
		size = 100,
		solo = false,
		touched = nil,
	}
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function opOf(ops: { raftplan.Op }, id: string): raftplan.Op?
	for _, op in ops do
		if table.find(op.issues, id) then
			return op
		end
	end
	return nil
end

return t.spec("f0399: a ticket is rafted with what it depends on", function(it)
	it("two features with no shared surface share a raft when one depends on the other", function()
		local a = cand("f0010", { touched = { "a/x.luau" } })
		local b = cand("f0011", { touched = { "b/y.luau" }, deps = { "f0010" } })
		local c = cand("f0012", { touched = { "c/z.luau" } })
		local ops = raftplan.plan({ a, b, c }, {})
		t.expect(#ops).toBe(2)
		t.expect((opOf(ops, "f0011") :: raftplan.Op).issues).toEqual({ "f0010", "f0011" })
		t.expect((opOf(ops, "f0012") :: raftplan.Op).issues).toEqual({ "f0012" })
		-- without the dependency they stay apart, as before
		local apart = raftplan.plan({ a, cand("f0011", { touched = { "b/y.luau" } }) }, {})
		t.expect(#apart).toBe(2)
	end)

	it("a feature folds into the open raft that holds what it depends on", function()
		local member = cand("f0010", { raft = "R0005", touched = { "a/x.luau" } })
		local b = cand("f0011", { touched = { "b/y.luau" }, deps = { "f0010" } })
		local open: raftplan.Raft = {
			id = "R0005",
			type = "feature",
			root = ROOT,
			state = "backlog",
			status = "prepared",
			single = false,
			members = { "f0010" },
		}
		local ops = raftplan.plan({ member, b }, { open })
		t.expect(#ops).toBe(1)
		t.expect(ops[1].kind).toBe("fold")
		t.expect(ops[1].raft).toBe("R0005")
		t.expect(ops[1].issues).toEqual({ "f0011" })
	end)

	it("the cap never splits a chore from what it depends on, and still splits what is free", function()
		local a = cand("c0010", { size = 900 })
		local b = cand("c0011", { size = 900, deps = { "c0010" } })
		local free = cand("c0012", { size = 900 })
		local ops = raftplan.plan({ a, b, free }, {})
		t.expect((opOf(ops, "c0011") :: raftplan.Op).issues).toEqual({ "c0010", "c0011" })
		t.expect((opOf(ops, "c0012") :: raftplan.Op).issues).toEqual({ "c0012" })
		-- no dependency: 900 + 900 passes the cap of 1,500, so two rafts, as before
		local two = raftplan.plan({ a, cand("c0011", { size = 900 }) }, {})
		t.expect(#two).toBe(2)
	end)

	it("a dependent with a lower id than its dependency still joins it", function()
		local late = cand("c0020", { size = 900 })
		local early = cand("c0010", { size = 900, deps = { "c0020" } })
		local ops = raftplan.plan({ early, late }, {})
		t.expect(#ops).toBe(1)
		t.expect(ops[1].issues).toEqual({ "c0020", "c0010" })
	end)

	it("another type, another project and a solo issue stay in their own rafts", function()
		local chore = cand("c0010")
		local feature = cand("f0011", { deps = { "c0010" } })
		local ops = raftplan.plan({ chore, feature }, {})
		t.expect(#ops).toBe(2)
		local other = cand("c0012", { root = "pickman/.tracker", deps = { "c0010" } })
		t.expect(#raftplan.plan({ chore, other }, {})).toBe(2)
		local solo = cand("c0013", { solo = true })
		local onSolo = cand("c0014", { deps = { "c0013" } })
		local soloOps = raftplan.plan({ solo, onSolo }, {})
		t.expect(#soloOps).toBe(2)
		t.expect((opOf(soloOps, "c0013") :: raftplan.Op).single).toBe(true)
		t.expect((opOf(soloOps, "c0014") :: raftplan.Op).issues).toEqual({ "c0014" })
	end)

	it("a dependency that is not a candidate changes nothing", function()
		local done = cand("c0009", { state = "done", status = "done" })
		local b = cand("c0011", { deps = { "c0009" } })
		local ops = raftplan.plan({ done, b }, {})
		t.expect(#ops).toBe(1)
		t.expect(ops[1].issues).toEqual({ "c0011" })
	end)
end)
