--!strict
-- c0277 final-review-001 F7: the dispatcher says a step's worktree was discarded only when a discard marker for the item sits in
-- the renamed family member (`<name>-discarded-<n>`); a folder someone removed is just gone. Fixture under .cache/c0277-marked.
local dispatcher = require("@znile/engine/dispatcher")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local BASE = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/c0277-marked`
local function marker(member: string, items: { string })
	fs.writeDir(`{BASE}/.worktree/{member}/.cache`)
	fs.writeFile(
		`{BASE}/.worktree/{member}/{heartbeat.DISCARDED}`,
		heartbeat.discardText({
			path = `{BASE}/.worktree/{member}`,
			copy = `{BASE}/.worktree/x-1`,
			branch = "b-discarded-1",
			base = "b",
			items = items,
			since = 1,
			pushedSha = "",
			pushed = {},
			unpushed = {},
			dirty = {},
		})
	)
end

return t.spec("c0277 the dispatcher tells a takeover from a removed folder", function(it)
	it("finds a marker for the item in the renamed member of the same family only", function()
		pcall(fs.removeDir, BASE)
		fs.writeDir(`{BASE}/.worktree`)
		local cwd = `{BASE}/.worktree/prep-a`
		t.expect(dispatcher.discardMarked(BASE, cwd, "c0010")).toBe(false) -- nothing renamed: a removed folder
		marker("prep-a-discarded-1", { "c0010", "c0020" })
		t.expect(dispatcher.discardMarked(BASE, cwd, "c0010")).toBe(true)
		t.expect(dispatcher.discardMarked(BASE, cwd, "c0020")).toBe(true)
		t.expect(dispatcher.discardMarked(BASE, cwd, "c0030")).toBe(false) -- another item
		marker("prep-b-discarded-1", { "c0030" })
		t.expect(dispatcher.discardMarked(BASE, cwd, "c0030")).toBe(false) -- another family
		fs.writeDir(`{BASE}/.worktree/prep-a-discarded-x`)
		t.expect(dispatcher.discardMarked(BASE, cwd, "c0040")).toBe(false)
		pcall(fs.removeDir, BASE)
	end)
end)
