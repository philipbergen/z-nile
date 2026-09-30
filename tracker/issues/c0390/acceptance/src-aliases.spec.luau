--!strict
-- c0390 AC5: which require specs src may use. Roblox reads no .luaurc, and @game outside
-- ReplicatedStorage either never replicates to clients (ServerScriptService) or loads a second copy
-- of a module (StarterPlayer). tests/meta applies this to every require in src.
local fs = require("@lune/fs")
local graph = require("@scripts/lib/graph")
local t = require("@tests/lib/t")

return t.spec("c0390 src alias rule", function(it)
	it("allows relative paths, @self/ and @game/ReplicatedStorage/", function()
		for _, spec in
			{
				"./Camera",
				"../Maze",
				"../../Movement",
				"@self/Layouts",
				"@game/ReplicatedStorage/Shared/Logic/Session",
				"@game/ReplicatedStorage/Remotes",
			}
		do
			t.expect(graph.srcAliasAllowed(spec)).toBe(true)
		end
	end)

	it("rejects other aliases and other @game roots", function()
		for _, spec in
			{
				"@logic/Maze",
				"@shared/Config",
				"@tests/lib/t",
				"@lune/fs",
				"@game/ServerScriptService/Server/Sessions",
				"@game/StarterPlayer/StarterPlayerScripts/Client/Camera",
				"@game/Workspace/Maze",
				"@game/ReplicatedStorageX/A",
				"@Game/ReplicatedStorage/Shared/Logic/Session",
				"@self",
				"@game",
				"Maze",
			}
		do
			t.expect(graph.srcAliasAllowed(spec)).toBe(false)
		end
	end)

	it("srcAliasViolations scans a directory's real requires, in either quote style", function()
		local DIR = ".cache/c0390-aliases"
		local R = "req" .. "uire" -- never write a literal require call here; the scanner would read it
		if fs.isDir(DIR) then
			fs.removeDir(DIR)
		end
		fs.writeDir(`{DIR}/sub`)
		fs.writeFile(
			`{DIR}/ok.luau`,
			`local A = {R}("@game/ReplicatedStorage/Shared/Logic/Maze")\nlocal B = {R}("./sub/x")\n`
		)
		fs.writeFile(
			`{DIR}/sub/bad.luau`,
			`local A = {R}( '@game/ServerScriptService/Server/Secret')\nlocal B = {R}("@logic/Maze")\n-- local C = {R}("@tests/lib/t")\n`
		)
		local ok, err = pcall(function()
			local got = graph.srcAliasViolations(DIR)
			t.expect(got).toEqual({
				{ file = `{DIR}/sub/bad.luau`, spec = "@game/ServerScriptService/Server/Secret" },
				{ file = `{DIR}/sub/bad.luau`, spec = "@logic/Maze" },
			})
		end)
		fs.removeDir(DIR)
		if not ok then
			error(err, 0)
		end
	end)

	it("tests/meta applies it to src", function()
		local meta = fs.readFile("tests/meta/architecture.spec.luau")
		t.expect(string.find(meta, 'graph.srcAliasViolations("src")', 1, true) ~= nil).toBe(true)
		t.expect(graph.srcAliasViolations("src")).toEqual({})
	end)
end)
