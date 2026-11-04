--!strict
-- c0184 AC1, the exact places of the five homes (check.sh runs it at done and never again; a game's first issues add
-- remotes and c0185 adds the library's mapping, so the promoted rule pins no tree):
--   lune run places.luau <checkout top>
-- arcade maps its two folders under ReplicatedStorage.Arcade and ServerStorage.Arcade, and nothing else. A game keeps
-- CharacterAutoLoads off and maps Shared, Server and Client to its three src folders, and nothing else.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local top = process.args[1]
local bad: { string } = {}

local function paths(node: any, into: { string })
	if type(node) ~= "table" then
		return
	end
	for key, value in node :: { [string]: any } do
		if key == "$path" and type(value) == "string" then
			table.insert(into, value)
		else
			paths(value, into)
		end
	end
end

local function check(home: string, want: { [string]: string }, autoLoads: boolean)
	local tree: any = (serde.decode("json", fs.readFile(`{top}/{home}/default.project.json`)) :: any).tree
	local found: { string } = {}
	paths(tree, found)
	if #found ~= 0 then
		local n = 0
		for _ in want do
			n += 1
		end
		if #found ~= n then
			table.insert(bad, `{home}: {#found} $paths, not {n}`)
		end
	end
	for location, path in want do
		local node: any = tree
		for seg in string.gmatch(location, "[^.]+") do
			node = if type(node) == "table" then node[seg] else nil
		end
		if type(node) ~= "table" or node["$path"] ~= path then
			table.insert(bad, `{home}: {location} is not {path}`)
		end
	end
	if autoLoads then
		local props: any = tree.Players and tree.Players["$properties"]
		if type(props) ~= "table" or props.CharacterAutoLoads ~= false then
			table.insert(bad, `{home}: Players.CharacterAutoLoads is not false`)
		end
	end
end

check(
	"arcade",
	{ ["ReplicatedStorage.Arcade"] = "src/shared", ["ServerStorage.Arcade"] = "src/server" },
	false
)
for _, game in { "portal", "snake", "invaders", "asteroids" } do
	check(game, {
		["ReplicatedStorage.Shared"] = "src/shared",
		["ServerScriptService.Server"] = "src/server",
		["StarterPlayer.StarterPlayerScripts.Client"] = "src/client",
	}, true)
end

if #bad > 0 then
	print(table.concat(bad, "\n"))
	process.exit(1)
end
