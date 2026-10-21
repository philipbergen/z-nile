--!strict
-- c0114 AC14: finished items' check.sh files name the moved paths' new locations (decided with the user, 2026-10-21:
-- "Rewrite finished files"; the user's exception to "sequestered files never change", for finished items only, in
-- c0114's PR). rewrites.luau is the one rewrite; finished.luau (run by check.sh) checks each file against its base text.
-- Reads the real tree, read-only.
local fs = require("@lune/fs")
local rewrites = require("./rewrites")
local t = require("@tests/lib/t")

local ROOTS = { "tracker", "z-nile/.tracker" }

-- every item id whose folder is under z-nile/.tracker, and every finished item's sequestered file
local function tree(): ({ [string]: boolean }, { string })
	local moved: { [string]: boolean } = {}
	local files: { string } = {}
	local function walk(dir: string)
		for _, name in fs.readDir(dir) do
			local p = `{dir}/{name}`
			if fs.isDir(p) then
				walk(p)
			else
				table.insert(files, p)
			end
		end
	end
	for _, root in ROOTS do
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local dir = `{root}/{kind}/{state}`
				if fs.isDir(dir) then
					for _, id in fs.readDir(dir) do
						if string.match(id, "^[fdcR]%d%d%d%d$") then
							if root ~= "tracker" then
								moved[id] = true
							end
							if state == "done/" then
								if fs.isFile(`{dir}{id}/check.sh`) then
									table.insert(files, `{dir}{id}/check.sh`)
								end
								if fs.isDir(`{dir}{id}/acceptance`) then
									walk(`{dir}{id}/acceptance`)
								end
							end
						end
					end
				end
			end
		end
	end
	return moved, files
end

return t.spec("c0114 finished items' check.sh files name the new paths", function(it)
	it("the rewrite moves each moved path, the command and the moved items, and nothing else", function()
		local moved = { c0005 = true, R0013 = true }
		local function rw(text: string): string
			return rewrites.paths(text, moved)
		end
		t.expect(rw('source "$(git rev-parse --show-toplevel)/scripts/lib/ac.sh"'))
			.toBe('source "$(git rev-parse --show-toplevel)/z-nile/lib/ac.sh"')
		t.expect(rw("check x scripts/tracker.sh members R0013")).toBe("check x ./zn members R0013")
		t.expect(rw('bash "$ROOT/scripts/tracker.sh" find')).toBe('bash "$ROOT/zn" find')
		t.expect(rw("grep -qF 'tracker.sh launch' x")).toBe("grep -qF './zn launch' x")
		t.expect(rw("scripts/check.sh --full")).toBe("z-nile/check.sh --full")
		t.expect(rw("grep x scripts/tracker/main.luau")).toBe("grep x z-nile/engine/main.luau")
		t.expect(rw("cat tracker/templates/prompt.md")).toBe("cat z-nile/templates/prompt.md")
		t.expect(rw("bash tracker/issues/done/c0005/check.sh"))
			.toBe("bash z-nile/.tracker/issues/done/c0005/check.sh")
		t.expect(rw("bash tracker/rafts/done/R0013/check.sh"))
			.toBe("bash z-nile/.tracker/rafts/done/R0013/check.sh")
		-- a game item, the game's scripts, the counter, a skill and a longer path stay
		for _, same in
			{
				"bash tracker/issues/done/f0010/check.sh",
				"scripts/runtime-test.luau scripts/lib/opencloud.luau scripts/deploy-beta.luau",
				"tracker/next tracker/architecture.md",
				".claude/skills/tracker/SKILL.md .claude/skills/tracker/templates",
				"my-scripts/check.sh tracker2/templates",
			}
		do
			t.expect(rw(same)).toBe(same)
		end
		-- applied twice, it changes nothing more
		local once = rw("scripts/tracker.sh find c0005; scripts/lib/fence.sh; tracker/issues/c0005")
		t.expect(rw(once)).toBe(once)
	end)

	it("every finished item's check.sh and acceptance file is already rewritten", function()
		local moved, files = tree()
		t.expect(#files > 100).toBe(true)
		for _, f in files do
			local text = fs.readFile(f)
			local settled = rewrites.paths(text, moved) == text
			-- an item whose special edits undo a rewrite (a spec case name) is settled when they give the same text
			local id = string.match(f, "/([fdcR]%d%d%d%d)/[^/]+$") :: string
			if not settled and rewrites.SPECIAL[id] then
				local ok, again = pcall(rewrites.expected, id, text, moved)
				settled = ok and again == text
			end
			if not settled then
				error(`{f} still names a moved path`)
			end
		end
	end)

	it("each special edit names a finished item and applies once", function()
		local moved = tree()
		for id, edits in rewrites.SPECIAL do
			t.expect(#edits > 0).toBe(true)
			local found = false
			for _, root in ROOTS do
				for _, kind in { "issues", "rafts" } do
					local f = `{root}/{kind}/done/{id}/check.sh`
					if fs.isFile(f) then
						found = true
						local text = fs.readFile(f)
						for _, e in edits do
							t.expect(string.find(text, e[2], 1, true) ~= nil).toBe(true)
						end
					end
				end
			end
			if not found then
				error(`SPECIAL {id}: no finished check.sh`)
			end
		end
		t.expect(moved.c0114).toBe(true)
	end)
end)
