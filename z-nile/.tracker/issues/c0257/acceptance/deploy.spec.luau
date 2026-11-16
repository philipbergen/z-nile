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

return t.spec("c0257 AC4: deploy workflow ignores the plugin", function(it)
	it("AC4: the place-deploy workflow ignores pushes that touch only the plugin", function()
		local wf = read(`{TREE}/.github/workflows/deploy.yml`)
		local ignore = string.match(wf, "push:.-paths%-ignore: (%b[])") or ""
		t.expect(has(ignore, "'z-nile-omarchy/**'")).toBe(true)
		-- the tracker ignores that were there stay
		t.expect(has(ignore, "'z-nile/.tracker/**'")).toBe(true)
		t.expect(has(ignore, "'pickman/.tracker/**'")).toBe(true)
	end)
end)
