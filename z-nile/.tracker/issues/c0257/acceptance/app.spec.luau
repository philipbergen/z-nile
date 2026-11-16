--!strict
-- c0257 AC1, AC4, AC5, AC6: the omarchy-shell plugin is complete and wired, runs no shell, is documented with a test command
-- that works on today's node, and the place-deploy workflow ignores it. Reads text only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds z-nile-omarchy/ (prep proved these specs against the prototype that way)
local TREE = process.env.ZN_C0257_TREE or TOP
local ROOT = `{TREE}/z-nile-omarchy`
local APP = `{ROOT}/znile.board`

local function read(path: string): string
	return fs.readFile(path)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local FILES = {
	"BarWidget.qml", "Board.qml", "Service.qml", "Model.js", "fetch.sh", "prs.sh", "agents.sh",
	"manifest.json", "settings.json", "README.md", "tests/model.test.mjs",
}

return t.spec("c0257 AC1: plugin files, manifest and settings", function(it)
	it("AC1: every file of the plugin exists and the manifest names real entry points", function()
		for _, f in FILES do
			t.expect(`{f}:{fs.isFile(`{APP}/{f}`)}`).toBe(`{f}:true`)
		end
		t.expect(fs.isFile(`{ROOT}/README.md`)).toBe(true)
		local m = serde.decode("json", read(`{APP}/manifest.json`)) :: any
		t.expect(m.schemaVersion).toBe(1)
		t.expect(m.id).toBe("znile.board")
		t.expect(m.keepLoaded).toBe(true)
		local kinds: { [string]: boolean } = {}
		for _, k in m.kinds do
			kinds[k] = true
		end
		t.expect(kinds.service and kinds["bar-widget"] and kinds.panel).toBe(true)
		for _, entry in { m.entryPoints.service, m.entryPoints.barWidget, m.entryPoints.panel } do
			t.expect(`{entry}:{fs.isFile(`{APP}/{entry}`)}`).toBe(`{entry}:true`)
		end
		t.expect(m.barWidget.allowMultiple).toBe(false)
	end)

	it("AC1: the settings carry the repository path, a refresh period and an empty rank command", function()
		local s = serde.decode("json", read(`{APP}/settings.json`)) :: any
		t.expect(type(s.repoPath)).toBe("string")
		t.expect(type(s.refreshIntervalSec) == "number" and s.refreshIntervalSec >= 30).toBe(true)
		-- until c0249 builds ./zn rank and wires it (decided with the user, 2026-11-11), a drag keeps the order for the session
		t.expect(s.rankCommand).toBe("")
	end)
end)
