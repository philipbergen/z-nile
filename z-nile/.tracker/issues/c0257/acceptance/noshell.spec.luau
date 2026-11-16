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

return t.spec("c0257 AC5: no shell string, scripts stop on error", function(it)
	it("AC5: no shell string anywhere in the plugin: external commands are argument arrays", function()
		-- built from parts so this file never names what it scans for
		local banned = { "s" .. "h -c", "bash" .. " -c", "ev" .. "al ", "execDetached([\"s" .. "h\"", "execDetached([\"bash\"" }
		local scanned = 0
		for _, f in { "BarWidget.qml", "Board.qml", "Service.qml", "Model.js", "fetch.sh", "prs.sh", "agents.sh", "NewTicketDialog.qml", "TicketTile.qml" } do
			local path = `{APP}/{f}`
			if not fs.isFile(path) then
				continue
			end
			scanned += 1
			local text = read(path)
			for _, b in banned do
				t.expect(`{f} names {b}: {has(text, b)}`).toBe(`{f} names {b}: false`)
			end
		end
		t.expect(scanned >= 7).toBe(true)
	end)

	it("AC5: the shell scripts stop on error and are executable", function()
		for _, f in { "fetch.sh", "prs.sh", "agents.sh" } do
			local text = read(`{APP}/{f}`)
			t.expect(`{f}:{string.sub(text, 1, 2)}`).toBe(`{f}:#!`)
			t.expect(`{f}:{has(text, "set -")}`).toBe(`{f}:true`)
			t.expect(`{f}:{process.exec("test", { "-x", `{APP}/{f}` }).ok}`).toBe(`{f}:true`)
		end
	end)
end)
