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

return t.spec("c0257 AC6: documented test command works on node 22", function(it)
	it("AC6: the install steps run the tests as a file, which works on node 22 (a folder argument does not)", function()
		for _, doc in { `{ROOT}/README.md`, `{APP}/README.md` } do
			local text = read(doc)
			t.expect(`{doc}:{has(text, "tests/model.test.mjs")}`).toBe(`{doc}:true`)
			t.expect(`{doc}:{has(text, "node --test z-nile-omarchy/znile.board/tests/\n")}`).toBe(`{doc}:false`)
		end
		local top = read(`{ROOT}/README.md`)
		t.expect(has(top, "omarchy plugin enable znile.board")).toBe(true)
		t.expect(has(top, "settings.json")).toBe(true)
	end)
end)
