--!strict
-- c0257 AC1: the omarchy-shell plugin is complete: the exact file set of z-nile-omarchy/ (no file missing, none unplanned),
-- a manifest whose entry points name real files, and settings that keep the rank command empty. Reads files only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds z-nile-omarchy/ (prep proved these specs against the prototype that way)
local ROOT = `{process.env.ZN_C0257_TREE or TOP}/z-nile-omarchy`
local APP = `{ROOT}/znile.board`

-- the 21 files of the prototype (e467e31), relative to z-nile-omarchy/
local EXPECTED = {
	"README.md",
	"znile.board/BarWidget.qml",
	"znile.board/Board.qml",
	"znile.board/Chip.qml",
	"znile.board/CopyBox.qml",
	"znile.board/IdChip.qml",
	"znile.board/IdLinks.qml",
	"znile.board/Model.js",
	"znile.board/NewTicketDialog.qml",
	"znile.board/PlainLabel.qml",
	"znile.board/README.md",
	"znile.board/Service.qml",
	"znile.board/SmoothWheel.qml",
	"znile.board/TicketTile.qml",
	"znile.board/TypeBadge.qml",
	"znile.board/agents.sh",
	"znile.board/fetch.sh",
	"znile.board/manifest.json",
	"znile.board/prs.sh",
	"znile.board/settings.json",
	"znile.board/tests/model.test.mjs",
}

local function walk(dir: string, prefix: string, out: { string })
	for _, name in fs.readDir(dir) do
		if fs.isDir(`{dir}/{name}`) then
			walk(`{dir}/{name}`, `{prefix}{name}/`, out)
		else
			table.insert(out, prefix .. name)
		end
	end
end

return t.spec("c0257 AC1: the plugin's files, manifest and settings", function(it)
	it("AC1: the folder holds exactly the planned files", function()
		local found: { string } = {}
		walk(ROOT, "", found)
		table.sort(found)
		t.expect(found).toEqual(EXPECTED)
	end)

	it("AC1: the manifest names real entry points", function()
		local m = serde.decode("json", fs.readFile(`{APP}/manifest.json`)) :: any
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
		local s = serde.decode("json", fs.readFile(`{APP}/settings.json`)) :: any
		t.expect(type(s.repoPath)).toBe("string")
		t.expect(type(s.refreshIntervalSec) == "number" and s.refreshIntervalSec >= 30).toBe(true)
		-- until c0249 builds ./zn rank and wires it (decided with the user, 2026-11-11), a drag keeps the order for the session
		t.expect(s.rankCommand).toBe("")
	end)
end)
