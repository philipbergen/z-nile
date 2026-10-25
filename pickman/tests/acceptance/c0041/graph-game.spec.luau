--!strict
-- c0390 AC1: graph maps Roblox's @game alias to files through the Rojo project's $path nodes.
-- c0120 override: the spec runs from its project's home after the move
local graph = require("@znile/lib/graph")
local t = require("@tests/lib/t")

-- c0120 override: this spec runs from pickman/; the graph fixture is z-nile's, z-nile/tests/fixtures/graph, so ../z-nile/ in front.
-- A project whose ReplicatedStorage.Shared is the existing graph fixture directory, with a nested
-- $path node that shadows its A directory: Shared.A is tests/fixtures/graph/B, as in Rojo.
-- c0120 override: the tooling's files live in z-nile/ (its home)
local PROJECT = {
	name = "fixture",
	tree = {
		["$className"] = "DataModel",
		ReplicatedStorage = {
			Shared = {
				["$path"] = "../z-nile/tests/fixtures/graph/", -- normalized to ../z-nile/tests/fixtures/graph
				A = { ["$path"] = "../z-nile/tests/fixtures/graph/B" },
			},
			-- a string prefix of "Graph": only a segment-boundary match keeps it out of Graph/...
			-- c0120 override: the spec runs from its home: the checkout's files are read from the top
			Gr = { ["$path"] = "../tests/fixtures/gr" },
		},
		ServerScriptService = { Server = { ["$path"] = "src/server" } },
		StarterPlayer = { StarterPlayerScripts = { Client = { ["$path"] = "src/client" } } },
	},
}

local function rootsMap(roots: { graph.GameRoot }): { [string]: string }
	local out: { [string]: string } = {}
	for _, r in roots do
		out[r.instance] = r.path
	end
	return out
end

return t.spec("c0390 graph @game", function(it)
	local roots = graph.gameRoots(PROJECT)

	it("lists every $path node as an instance path and a repo path", function()
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		t.expect(rootsMap(roots)).toEqual({
			["ReplicatedStorage/Shared"] = "../z-nile/tests/fixtures/graph",
			["ReplicatedStorage/Shared/A"] = "../z-nile/tests/fixtures/graph/B",
			["ReplicatedStorage/Gr"] = "../tests/fixtures/gr",
			["ServerScriptService/Server"] = "src/server",
			["StarterPlayer/StarterPlayerScripts/Client"] = "src/client",
		})
	end)

	it("orders roots by instance path length, longest first", function()
		-- not by filesystem path length: Server has the longest instance path but the shortest path
		for i = 2, #roots do
			if #roots[i].instance > #roots[i - 1].instance then
				error(`roots[{i}] {roots[i].instance} is longer than roots[{i - 1}] {roots[i - 1].instance}`)
			end
		end
	end)

	it("reads default.project.json when no project is given", function()
		local real = rootsMap(graph.gameRoots())
		t.expect(real["ReplicatedStorage/Shared"]).toBe("src/shared")
		t.expect(real["ServerScriptService/Server"]).toBe("src/server")
		t.expect(real["StarterPlayer/StarterPlayerScripts/Client"]).toBe("src/client")
		-- a cached default never replaces an explicit project
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		t.expect(rootsMap(graph.gameRoots(PROJECT))["ReplicatedStorage/Shared"])
			.toBe("../z-nile/tests/fixtures/graph")
	end)

	it("resolves modules and init directories under a mapped instance", function()
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Shared/B", roots))
			.toBe("../z-nile/tests/fixtures/graph/B/init.luau")
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Shared/a_check", roots))
			.toBe("../z-nile/tests/fixtures/graph/a_check.luau")
	end)

	it("the longest mapped node owns its subtree, with no fallback to a shorter one", function()
		-- Shared.A is mapped to .../B, so it resolves there, not to .../A/init.luau
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Shared/A", roots))
			.toBe("../z-nile/tests/fixtures/graph/B/init.luau")
		-- .../B has no Impl; .../A/Impl.luau exists but belongs to the shadowed directory
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Shared/A/Impl", roots)).toBe(nil)
	end)

	it("matches mapped instance paths on segment boundaries only", function()
		t.expect(graph.resolveGame("@game/ReplicatedStorage/SharedX/a_check", roots)).toBe(nil)
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Shar/a_check", roots)).toBe(nil)
		-- "ReplicatedStorage/Gr" is a string prefix of this path; string-prefix matching would map it
		-- to tests/fixtures/gr .. "aph/A" = tests/fixtures/graph/A/init.luau, which exists
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Graph/A", roots)).toBe(nil)
	end)

	it("returns nil for missing modules, unmapped instances and scripts", function()
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Shared/Nope", roots)).toBe(nil)
		t.expect(graph.resolveGame("@game/ReplicatedStorage/Missing/A", roots)).toBe(nil)
		t.expect(graph.resolveGame("@game/ReplicatedStorage", roots)).toBe(nil)
		t.expect(graph.resolveGame("@game/Workspace/A", roots)).toBe(nil)
		-- src/server/Main.server.luau is a Script, not a ModuleScript, under either name
		t.expect(graph.resolveGame("@game/ServerScriptService/Server/Main", roots)).toBe(nil)
		t.expect(graph.resolveGame("@game/ServerScriptService/Server/Main.server", roots)).toBe(nil)
		t.expect(graph.resolveGame("@game/StarterPlayer/StarterPlayerScripts/Client/Main", roots)).toBe(nil)
		t.expect(graph.resolveGame("@game/StarterPlayer/StarterPlayerScripts/Client/Main.client", roots))
			.toBe(nil)
	end)

	it("rejects malformed paths", function()
		for _, spec in
			{
				"@game",
				"@game/",
				"@game/ReplicatedStorage//Shared/A",
				"@game/ReplicatedStorage/Shared/./A",
				"@game/ReplicatedStorage/Shared/../Shared/A",
				"@game/ReplicatedStorage/Shared/A/",
			}
		do
			t.expect(graph.resolveGame(spec, roots)).toBe(nil)
		end
	end)

	it("ignores specs that are not @game", function()
		t.expect(graph.resolveGame("./A", roots)).toBe(nil)
		t.expect(graph.resolveGame("@tests/lib/t", roots)).toBe(nil)
		t.expect(graph.resolveGame("@gamer/ReplicatedStorage/Shared/a_check", roots)).toBe(nil)
		t.expect(graph.resolveGame("@Game/ReplicatedStorage/Shared/a_check", roots)).toBe(nil)
		t.expect(graph.resolveGame("@GAME/ReplicatedStorage/Shared/a_check", roots)).toBe(nil)
	end)
end)
