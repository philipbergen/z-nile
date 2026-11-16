--!strict
-- c0251: which model line an id belongs to. A family is a model line (opus, fable, sonnet, kimi, grok, deepseek), kept as a
-- prefix table in `.models.toml` (`[families]`) the user edits. Pure: ids and the table in, a family out. This is the one
-- function that maps an id to a family; every other module (the picker, the dry-run, the board) asks it.

local family = {}

export type Families = { [string]: { string } } -- family -> id prefixes

-- `models.bareModel` (one trailing context marker `[...]` removed), spelt here because models.luau requires this module.
local function bare(id: string): string
	return (string.gsub(id, "%[[^%[%]]*%]$", ""))
end

-- The family of the longest prefix that matches the bare model id, or nil when none matches. Two families holding the same
-- prefix (two files can) are broken by name, so the answer never depends on table order.
function family.of(id: string, f: Families): string?
	local model = bare(id)
	local best: string? = nil
	local bestLen = 0
	for name, prefixes in f do
		for _, prefix in prefixes do
			if prefix ~= "" and string.sub(model, 1, #prefix) == prefix then
				if #prefix > bestLen or (#prefix == bestLen and best ~= nil and name < best) then
					best, bestLen = name, #prefix
				end
			end
		end
	end
	return best
end

-- True when both sides name a family and it is the same one: an unknown family is never the same as anything.
function family.same(a: string?, b: string?): boolean
	return a ~= nil and b ~= nil and a == b
end

return family
