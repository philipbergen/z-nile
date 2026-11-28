--!strict
-- f0421 escape (2026-11-24): agy was added as a worker CLI without its agent marker, so the person-only acts (approve,
-- --apply) did not refuse an agy session. Every worker CLI (models.CLIS) now owns at least one marker in agentenv,
-- whose OWNERS is the one definition of which marker a CLI sets; MARKERS is read from it.
local agentenv = require("@znile/engine/agentenv")
local fence = require("@tests/lib/fence")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

return t.spec("agentenv: every worker CLI has an agent marker", function(it)
	it("every name in models.CLIS owns at least one marker", function()
		local owned: { [string]: boolean } = {}
		for _, pair in agentenv.OWNERS do
			owned[pair[2]] = true
		end
		local missing: { string } = {}
		for _, cli in models.CLIS do
			if not owned[cli] then
				table.insert(missing, cli)
			end
		end
		t.expect(`missing: {table.concat(missing, " ")}`).toBe("missing: ")
	end)

	it("every owner is a worker CLI, and MARKERS is the owned markers in their order, each once", function()
		local names: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, pair in agentenv.OWNERS do
			t.expect(`{pair[2]}: {table.find(models.CLIS, pair[2]) ~= nil}`).toBe(`{pair[2]}: true`)
			t.expect(`{pair[1]} once: {seen[pair[1]] == nil}`).toBe(`{pair[1]} once: true`)
			seen[pair[1]] = true
			table.insert(names, pair[1])
		end
		t.expect(table.concat(agentenv.MARKERS, " ")).toBe(table.concat(names, " "))
	end)

	it("an agy session is marked by ANTIGRAVITY_AGENT", function()
		local owner: string? = nil
		for _, pair in agentenv.OWNERS do
			if pair[1] == "ANTIGRAVITY_AGENT" then
				owner = pair[2]
			end
		end
		t.expect(owner).toBe("agy")
		t.expect(agentenv.firstSet({ ANTIGRAVITY_AGENT = "1" }, agentenv.MARKERS)).toBe("ANTIGRAVITY_AGENT")
	end)

	-- the promoted terminal fixtures (c0369's approve specs) clear the markers by hand and do not name agy's, so the
	-- runner clears it: a gate run from an agy session must not look like an agent's terminal to them
	it("the runner clears agy's marker for every spec", function()
		for _, pair in agentenv.OWNERS do
			if pair[2] == "agy" then
				t.expect(`{pair[1]}: {table.find(fence.CLI_VARS, pair[1]) ~= nil}`).toBe(`{pair[1]}: true`)
				t.expect(`{pair[1]}={process.env[pair[1]] or "<unset>"}`).toBe(`{pair[1]}=<unset>`)
			end
		end
	end)
end)
