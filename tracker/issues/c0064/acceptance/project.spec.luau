--!strict
-- c0064 AC2: the copy of a Rojo project that the deploy builds. Every `$path` points at the checkout from
-- anywhere, the place ids are written on ServerScriptService, and nothing else changes: the real lobby
-- project, copied with the game place's id and built from a folder outside the checkout's root, is the
-- checked-in lobby with only that attribute changed.
local Beta = require("@scripts/lib/beta")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
local work = `{root}/.cache/c0064-project`

local function decode(text: string): any
	return serde.decode("json" :: "json", text)
end

local SAMPLE = [[{
  "name": "sample",
  "globIgnorePaths": ["**/*.tmp"],
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": { "Shared": { "$path": "src/shared" }, "Abs": { "$path": "/opt/x" } },
    "ServerScriptService": {
      "$attributes": { "Keep": 5, "GamePlaceId": 0 },
      "Lobby": { "$path": "src/lobby/server", "Deep": { "$path": { "optional": "src/maybe" } } }
    },
    "Workspace": { "$properties": { "Gravity": 50 } }
  }
}]]

-- name/class of every instance under the DataModel, sorted, with ServerScriptService's attributes
local function shape(game: any): ({ string }, { [string]: any })
	local out: { string } = {}
	for _, d in game:GetDescendants() do
		local src = if d:IsA("LuaSourceContainer") then (d :: any).Source else ""
		table.insert(out, `{d:GetFullName()} {d.ClassName} {#src}`)
	end
	table.sort(out)
	return out, game:GetService("ServerScriptService"):GetAttributes()
end

local function build(project: string): any
	local out = `{work}/{math.random(1, 1e9)}.rbxl`
	local r = process.exec("rojo", { "build", project, "-o", out })
	assert(r.ok, `rojo build {project} failed: {r.stderr}{r.stdout}`)
	local game = roblox.deserializePlace(fs.readFile(out))
	fs.removeFile(out)
	return game
end

return t.spec("c0064 Beta.project", function(it)
	fs.writeDir(work)

	it(
		"makes every relative $path absolute against the project's folder, and leaves absolute ones",
		function()
			local copy = decode(Beta.project(SAMPLE, "/repo", {}))
			t.expect(copy.tree.ReplicatedStorage.Shared["$path"]).toBe("/repo/src/shared")
			t.expect(copy.tree.ReplicatedStorage.Abs["$path"]).toBe("/opt/x")
			t.expect(copy.tree.ServerScriptService.Lobby["$path"]).toBe("/repo/src/lobby/server")
			t.expect(copy.tree.ServerScriptService.Lobby.Deep["$path"])
				.toEqual({ optional = "/repo/src/maybe" })
		end
	)

	it("writes the attributes beside the ones ServerScriptService has, and changes nothing else", function()
		local copy = decode(Beta.project(SAMPLE, "/repo", { GamePlaceId = 4815162342 }))
		t.expect(copy.tree.ServerScriptService["$attributes"]).toEqual({ Keep = 5, GamePlaceId = 4815162342 })
		local want = decode(SAMPLE)
		want.tree.ReplicatedStorage.Shared["$path"] = "/repo/src/shared"
		want.tree.ServerScriptService.Lobby["$path"] = "/repo/src/lobby/server"
		want.tree.ServerScriptService.Lobby.Deep["$path"] = { optional = "/repo/src/maybe" }
		want.tree.ServerScriptService["$attributes"].GamePlaceId = 4815162342
		t.expect(copy).toEqual(want)
	end)

	it("adds ServerScriptService and its attributes when the project has none", function()
		local text =
			'{"name":"g","tree":{"$className":"DataModel","Workspace":{"$properties":{"Gravity":1}}}}'
		local copy = decode(Beta.project(text, "/repo", { GamePlaceId = 7 }))
		t.expect(copy.tree.ServerScriptService).toEqual({ ["$attributes"] = { GamePlaceId = 7 } })
		t.expect(copy.tree.Workspace).toEqual({ ["$properties"] = { Gravity = 1 } })
		-- with no attributes the tree gets no ServerScriptService
		t.expect(decode(Beta.project(text, "/repo", {})).tree.ServerScriptService).toBe(nil)
	end)

	it("a large place id survives the copy exactly", function()
		local copy = decode(Beta.project(SAMPLE, "/repo", { GamePlaceId = 9007199254740991 }))
		t.expect(copy.tree.ServerScriptService["$attributes"].GamePlaceId).toBe(9007199254740991)
	end)

	it("text that is not a Rojo project fails", function()
		t.expect(function()
			Beta.project('{"name":"x"}', "/repo", {})
		end).toThrow("project")
		t.expect(function()
			Beta.project("not json", "/repo", {})
		end).toThrow()
	end)

	it(
		"the real lobby, copied with the game's id and built elsewhere, differs only in GamePlaceId",
		function()
			local text = fs.readFile(`{root}/lobby.project.json`)
			fs.writeFile(`{work}/lobby.project.json`, Beta.project(text, root, { GamePlaceId = 4815162342 }))
			local copied, copiedAttrs = shape(build(`{work}/lobby.project.json`))
			local original, originalAttrs = shape(build(`{root}/lobby.project.json`))
			t.expect(#copied > 20).toBe(true) -- the scripts and the shared Logic came along
			t.expect(copied).toEqual(original)
			t.expect(originalAttrs).toEqual({ GamePlaceId = 0 })
			t.expect(copiedAttrs).toEqual({ GamePlaceId = 4815162342 })
			t.expect(fs.readFile(`{root}/lobby.project.json`)).toBe(text) -- the checked-in project is unchanged
		end
	)

	it("the real game place, copied with no attributes and built elsewhere, is the same place", function()
		local text = fs.readFile(`{root}/default.project.json`)
		fs.writeFile(`{work}/game.project.json`, Beta.project(text, root, {}))
		local copied, copiedAttrs = shape(build(`{work}/game.project.json`))
		local original, originalAttrs = shape(build(`{root}/default.project.json`))
		t.expect(copied).toEqual(original)
		t.expect(copiedAttrs).toEqual(originalAttrs)
	end)
end)
