--!strict
-- f0437 step 5: the one writer of themes.json (the app's themes overview). It runs where the board page is rebuilt, from the
-- model that page was made from: `./zn sync` in the main checkout (which `land` runs) and `./zn board`. That read is already
-- paid for, makes no model call and no fetch, and sees the tracker as the checkout has it. The live folder is approvewalk's
-- one (an absolute ZN_LIVE_DIR, else the main checkout's .cache/live, and never when the live layer is off).
local approvalfacts = require("./approvalfacts")
local approvewalk = require("./approvewalk")
local board = require("./board")
local fs = require("@lune/fs")
local livecall = require("./livecall")
local sh = require("../lib/sh")
local stdio = require("@lune/stdio")
local themefacts = require("./themefacts")

local themewrite = {}

-- The theme definitions of the model, per project in the registry's order, each project's in tributaries.toml order.
local function defsOf(model: board.Model): { themefacts.ThemeDef }
	local defs: { themefacts.ThemeDef } = {}
	for _, p in model.projects do
		local rows: { board.TributaryRow } = model.tributaries[p.name] or {}
		for _, row in rows do
			if not row.implicit then
				table.insert(defs, { project = p.name, name = row.name, purpose = row.purpose })
			end
		end
	end
	return defs
end

-- Writes `<dir>/themes.json` from the model and the approval facts beside it (when they read), through a temporary file and
-- a rename. Returns the path.
function themewrite.write(dir: string, model: board.Model): string
	fs.writeDir(dir)
	local waiting: themefacts.Waiting? = nil
	local approvals = `{dir}/{approvalfacts.FILE}`
	if fs.isFile(approvals) then
		waiting = themefacts.waiting(fs.readFile(approvals))
	end
	local units =
		themefacts.units(model, if waiting then (waiting :: themefacts.Waiting).units else {}, model.live)
	local facts = themefacts.build({
		at = os.time(),
		themes = defsOf(model),
		units = units,
		approvalsAt = if waiting then (waiting :: themefacts.Waiting).at else nil,
		approvalsScope = if waiting then (waiting :: themefacts.Waiting).scope else "",
		live = model.live ~= nil,
	})
	local path = `{dir}/{themefacts.FILE}`
	sh.writeReplacing(path, themefacts.encode(facts))
	return path
end

-- The board refresh's step: write the facts where the live layer reads them and wake its listeners. It never fails the
-- refresh: when it cannot, the old file is removed (the view must never show earlier facts as current) and one line says so.
function themewrite.refresh(root: string, model: board.Model)
	local dir = approvewalk.liveDir(root)
	if not dir then
		return
	end
	local ok, err = pcall(themewrite.write, dir, model)
	if ok then
		livecall.poke("themes", "")
		return
	end
	pcall(fs.removeFile, `{dir}/{themefacts.FILE}`)
	local first = string.match(tostring(err), "[^\n]+") or "unknown"
	stdio.ewrite(
		`warning: theme facts not written ({first}): the app's themes view shows none until the board refresh succeeds\n`
	)
end

return themewrite
