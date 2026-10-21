--!strict
-- The id an item has now, for a spec that pins a real tracker item by the id it had before a compaction (c0870):
-- mapped through z-nile/compaction.txt (tracker/compaction.txt before c0114), read from the checkout (the spec's working directory) unless `mapText` is
-- given. Identity when there is no map or the map does not name the id; a malformed map is an error.
-- Self-contained on purpose: c0640's fence spec copies tests/lib without scripts/, and repo-fence.spec requires this.
-- The format is ids.parseMap's (z-nile/engine/ids.luau): `# comment` lines and `<old> <new>` lines.
local fs = require("@lune/fs")

local renamed = {}

-- the map's home since c0114, and before it (a tree from before the move)
local MAP_FILES = { "z-nile/compaction.txt", "tracker/compaction.txt" }
-- A spec in a project's home (pickman/, c0120) runs there, below the checkout's root: the root of the tree holding
-- this file (two folders up from tests/lib/) is read when the working directory has no map.
local ROOT = string.match(debug.info(1, "s"), "^(.*)/[^/]+/[^/]+/[^/]+$") or "."

local function parse(text: string): { [string]: string }?
	local map: { [string]: string } = {}
	local seen: { [string]: boolean } = {}
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, 1) ~= "#" then
			local old, new = string.match(line, "^([fdcR]%d%d%d%d) ([fdcR]%d%d%d%d)$")
			if
				not old
				or not new
				or string.sub(old, 1, 1) ~= string.sub(new, 1, 1)
				or map[old]
				or seen[new]
			then
				return nil
			end
			map[old] = new
			seen[new] = true
		end
	end
	return map
end

function renamed.id(old: string, mapText: string?): string
	local text = mapText
	local file = MAP_FILES[1]
	if text == nil then
		for _, base in { "", `{ROOT}/` } do
			for _, f in MAP_FILES do
				if text == nil and fs.isFile(base .. f) then
					text, file = fs.readFile(base .. f), base .. f
				end
			end
		end
	end
	if text == nil then
		return old
	end
	local map = parse(text)
	if not map then
		error(`{file}: the compaction map does not parse`, 2)
	end
	return map[old] or old
end

return renamed
