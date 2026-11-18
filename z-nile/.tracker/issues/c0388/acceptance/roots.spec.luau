--!strict
-- c0388: c0042's cli spec compares the board page with the raft and issue folders on disk. The folders come from
-- `tests/acceptance/c0042/ondisk.luau`, which reads the roots from the registry of the checkout it is given. Proved
-- on a fixture tree under .cache (plain folders and one registry file: no repository, no git).
local fs = require("@lune/fs")
local ondisk = require("@tests/acceptance/c0042/ondisk")
local t = require("@tests/lib/t")

local FX = ".cache/c0388-roots"

local function registry(names: { string }, retired: string): string
	local out = { `retired = [{retired}]`, "" }
	for _, name in names do
		table.insert(out, "[[project]]")
		table.insert(out, `name = "{name}"`)
		table.insert(out, `root = "{name}/.tracker"`)
		table.insert(out, "")
	end
	return table.concat(out, "\n")
end

local function dir(rel: string)
	fs.writeDir(`{FX}/{rel}`)
end

-- three registered roots, one retired root and one folder nobody registered
local function build(names: { string })
	if fs.isDir(FX) then
		fs.removeDir(FX)
	end
	dir("z-nile")
	fs.writeFile(`{FX}/z-nile/projects.toml`, registry(names, '"tracker"'))
	-- pickman: every state, and names that are not items
	dir("pickman/.tracker/rafts/R0001")
	dir("pickman/.tracker/rafts/active/R0002")
	dir("pickman/.tracker/rafts/done/R0003")
	dir("pickman/.tracker/rafts/retired/R0009")
	dir("pickman/.tracker/rafts/notes")
	dir("pickman/.tracker/rafts/R12")
	dir("pickman/.tracker/rafts/R00010")
	dir("pickman/.tracker/issues/f0001")
	dir("pickman/.tracker/issues/active/d0002")
	dir("pickman/.tracker/issues/done/c0003")
	dir("pickman/.tracker/issues/x0004")
	dir("pickman/.tracker/issues/c00050")
	-- a closed issue (won't do) keeps its folder and the page drops it (c0278); an open one has a document; a folder
	-- with no document at all is still listed, raft or issue (c0388 G3: the case then goes red on it, as it should)
	dir("pickman/.tracker/issues/c0011")
	fs.writeFile(
		`{FX}/pickman/.tracker/issues/c0011/c0011.md`,
		"---\nid: c0011\nstatus: closed-one-two-three\nwont_do: moot\n---\n"
	)
	dir("pickman/.tracker/issues/active/d0012")
	fs.writeFile(
		`{FX}/pickman/.tracker/issues/active/d0012/d0012.md`,
		"---\nid: d0012\nstatus: preparing-one-two-three\n---\n"
	)
	fs.writeFile(`{FX}/pickman/.tracker/issues/README.md`, "not an item\n")
	-- z-nile: a backlog only
	dir("z-nile/.tracker/rafts/R0004")
	dir("z-nile/.tracker/issues/c0005")
	-- arcade: one raft, no active/, no done/, no issues/ folder at all
	dir("arcade/.tracker/rafts/R0005")
	-- snake: registered only by the cases that name it
	dir("snake/.tracker/rafts/done/R0006")
	dir("snake/.tracker/issues/active/f0006")
	-- a retired root, and a folder no registry line names
	dir("tracker/rafts/R0008")
	dir("tracker/issues/c0008")
	dir("unregistered/.tracker/rafts/R0007")
	dir("unregistered/.tracker/issues/c0007")
end

local function sorted(list: { string }): { string }
	local out = table.clone(list)
	table.sort(out)
	return out
end

return t.spec("c0388 the folders c0042's cli spec counts come from every registered root", function(it)
	it("lists the raft and issue folders of every registered root: backlog, active and done", function()
		build({ "pickman", "z-nile", "arcade" })
		local found = ondisk.items(FX)
		t.expect(sorted(found.rafts)).toEqual({ "R0001", "R0002", "R0003", "R0004", "R0005" })
		t.expect(sorted(found.issues)).toEqual({ "c0003", "c0005", "d0002", "d0012", "f0001" })
		fs.removeDir(FX)
	end)

	it("leaves out a closed issue and keeps an open one and one with no document", function()
		build({ "pickman", "z-nile", "arcade" })
		local found = ondisk.items(FX)
		t.expect(table.find(found.issues, "c0011")).toBe(nil)
		t.expect(table.find(found.issues, "d0012") ~= nil).toBe(true)
		t.expect(table.find(found.issues, "f0001") ~= nil).toBe(true)
		fs.removeDir(FX)
	end)

	it("skips a folder a root does not have, without an error", function()
		build({ "arcade" })
		local ok, found = pcall(ondisk.items, FX)
		t.expect(ok).toBe(true)
		t.expect((found :: ondisk.Items).rafts).toEqual({ "R0005" })
		t.expect((found :: ondisk.Items).issues).toEqual({})
		fs.removeDir(FX)
	end)

	it("reads a root the moment the registry names it, and never one it does not name", function()
		build({ "pickman", "z-nile", "arcade" })
		local before = ondisk.items(FX)
		t.expect(table.find(before.rafts, "R0006")).toBe(nil)
		t.expect(table.find(before.issues, "f0006")).toBe(nil)
		fs.writeFile(
			`{FX}/z-nile/projects.toml`,
			registry({ "pickman", "z-nile", "arcade", "snake" }, '"tracker"')
		)
		local after = ondisk.items(FX)
		t.expect(sorted(after.rafts)).toEqual({ "R0001", "R0002", "R0003", "R0004", "R0005", "R0006" })
		t.expect(sorted(after.issues)).toEqual({ "c0003", "c0005", "d0002", "d0012", "f0001", "f0006" })
		fs.removeDir(FX)
	end)

	it("refuses a checkout with no registry instead of guessing the roots", function()
		build({ "pickman", "z-nile", "arcade" })
		fs.removeFile(`{FX}/z-nile/projects.toml`)
		local ok = pcall(ondisk.items, FX)
		t.expect(ok).toBe(false)
		fs.removeDir(FX)
	end)

	it("c0042's cli spec takes its folders from the module and names no tracker root itself", function()
		local text = fs.readFile("tests/acceptance/c0042/cli.spec.luau")
		t.expect(string.find(text, 'quire("./ond' .. 'isk")', 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "ondisk.items(TOP)", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "t.expect(rafts).toBe(#found.rafts)", 1, true) ~= nil).toBe(true)
		-- the issue half: the loop over the module's issues, the page lookup, and the assertion on what is missing
		t.expect(string.find(text, "for _, id in found.issues do", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "if m.home[id] == nil then", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, 't.expect(table.concat(missing, " ")).toBe("")', 1, true) ~= nil).toBe(true)
		t.expect((string.find(text, ".tracker/", 1, true))).toBe(nil)
		t.expect((string.find(text, "fs.readDir", 1, true))).toBe(nil)
	end)
end)
