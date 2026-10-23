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

-- The project root of an item directory `<root>/<issues|rafts>/[active/|done/]<ID>`, or nil.
function paths.rootOf(dir: string): string?
	return string.match(dir, "^(.+)/issues/[^/]+$")
		or string.match(dir, "^(.+)/issues/[^/]+/[^/]+$")
		or string.match(dir, "^(.+)/rafts/[^/]+$")
		or string.match(dir, "^(.+)/rafts/[^/]+/[^/]+$")
end

-- Every item path `<root>/<issues|rafts>/[active/|done/]<ID>` in `text` whose ID is a key of `dirs`, whose kind matches
-- the kind in `dirs[ID]` and whose root is the root of `dirs[ID]`, becomes `dirs[ID]` (for example
-- "z-nile/.tracker/issues/active/c0001"). A root counts only where it starts a path segment: the character before it is
-- not a letter, digit, `.`, `_` or `-` (so `tracker/` inside `z-nile/.tracker/` is never taken for the root `tracker`,
-- c0114). A path is an ID only when the character after it is not a letter, digit, `_` or `-` (so `c00100` and
-- `c0001-x` are left alone). A move never changes an item's root, so a path under another root is left alone.
function paths.rewrite(text: string, dirs: { [string]: string }): string
	local roots: { string } = {}
	for _, d in dirs do
		local r = paths.rootOf(d)
		if r and not table.find(roots, r) then
			table.insert(roots, r)
		end
	end
	local out: { string } = {}
	local pos = 1
	while true do
		local bestS: number? = nil
		local bestRoot = ""
		for _, r in roots do
			local from = pos
			while true do
				local s = string.find(text, r .. "/", from, true)
				if not s then
					break
				end
				local before = if s > 1 then string.sub(text, s - 1, s - 1) else ""
				if before == "" or not string.match(before, "[%w%._%-]") then
					if not bestS or s < bestS then
						bestS, bestRoot = s, r
					end
					break
				end
				from = s + 1
			end
		end
		if not bestS then
			break
		end
		local s = bestS :: number
		local after = s + #bestRoot + 1 -- the first character after `<root>/`
		local kind = string.match(text, "^(%a+)/", after)
		local id, stop = nil, nil
		if kind == "issues" or kind == "rafts" then
			id, stop = itemAt(string.sub(text, after + #kind + 1), kind)
		end
		local target = if id then dirs[id] else nil
		if id and stop and target and paths.rootOf(target) == bestRoot then
			table.insert(out, string.sub(text, pos, s - 1))
			table.insert(out, target)
			pos = after + #(kind :: string) + 1 + stop
		else
			table.insert(out, string.sub(text, pos, s))
			pos = s + 1
		end
	end
	table.insert(out, string.sub(text, pos))
	return table.concat(out)
end

return paths
