--!strict
-- Item paths inside a check.sh (pure, no I/O). When an item moves between backlog, active/ and done/, the paths in its
-- check.sh that name it follow. publish's move validation recomputes this, so the writer and the validator agree.
local paths = {}

-- The id at the start of `s` and the length of the item path it ends, when `s` begins `[active/|done/]<ID>` with the
-- id matching `kind` ("issues" or "rafts") and followed by something that doesn't continue the id.
local function itemAt(s: string, kind: string): (string?, number?)
	for _, state in { "active/", "done/", "" } do
		if string.sub(s, 1, #state) == state then
			local id = if kind == "issues"
				then string.match(s, "^[fdc]%d%d%d%d", #state + 1)
				else string.match(s, "^R%d%d%d%d", #state + 1)
			if id then
				local stop = #state + #id
				if not string.match(string.sub(s, stop + 1, stop + 1), "[%w_%-]") then
					return id, stop
				end
			end
		end
	end
	return nil, nil
end

-- Every item path `tracker/<issues|rafts>/[active/|done/]<ID>` in `text` whose ID is a key of `dirs`, and whose kind
-- matches the kind in `dirs[ID]`, becomes `dirs[ID]` (for example "tracker/issues/active/c0001"). A path is an ID
-- only when the character after it is not a letter, digit, `_` or `-` (so `c00100` and `c0001-x` are left alone).
function paths.rewrite(text: string, dirs: { [string]: string }): string
	local out: { string } = {}
	local pos = 1
	while true do
		local s, e, kind = string.find(text, "tracker/(%a+)/", pos)
		if not s or not e or not kind then
			break
		end
		local id, stop = nil, nil
		if kind == "issues" or kind == "rafts" then
			id, stop = itemAt(string.sub(text, e + 1), kind)
		end
		local target = if id then dirs[id] else nil
		if id and stop and target then
			table.insert(out, string.sub(text, pos, s - 1))
			table.insert(out, target)
			pos = e + stop + 1
		else
			table.insert(out, string.sub(text, pos, e))
			pos = e + 1
		end
	end
	table.insert(out, string.sub(text, pos))
	return table.concat(out)
end

return paths
