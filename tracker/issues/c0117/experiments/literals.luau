--!strict
-- The hyphenated literals the specs replace. A Lua pattern would replace nothing.
local function swap(text: string, old: string, new: string): string
	local out = ""
	local rest = text
	while true do
		local at = string.find(rest, old, 1, true)
		if not at then
			return out .. rest
		end
		out ..= string.sub(rest, 1, at - 1) .. new
		rest = string.sub(rest, at + #old)
	end
end

local ten = "| 2 | design-review | 12 | grok-4.7 |"
local blank = swap(ten, "grok-4.7", "")
local changed = swap(ten, "grok-4.7", "other-model")
if string.find(blank, "grok-4.7", 1, true) or not string.find(changed, "other-model", 1, true) then
	error("model literal")
end
local active = swap(
	"status: new-quiet-copper-falcon",
	"status: new-quiet-copper-falcon",
	"status: active-quiet-copper-falcon"
)
if active ~= "status: active-quiet-copper-falcon" then
	error(active)
end
local plain = swap("project: z-nile", "project: z-nile", "project: pickman")
if plain ~= "project: pickman" then
	error(plain)
end
print("pass")
