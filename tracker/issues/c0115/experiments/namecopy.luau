--!strict
-- Proves the frontmatter comparison used by names.spec. A hyphen in the skill name must not be a pattern.
local function withoutName(s: string): string
	local block, rest = string.match(s, "^(%-%-%-\n.-\n%-%-%-\n)(.*)$")
	if not block or not rest then
		return s
	end
	local kept = {}
	for line in string.gmatch(block, "(.-)\n") do
		if string.match(line, "^name: ") == nil then
			table.insert(kept, line)
		end
	end
	return table.concat(kept, "\n") .. "\n" .. rest
end

local source = "---\nname: make-issue\ndescription: Capture.\n---\n\n# Make an issue\nname: review\n"
local copy = "---\nname: z-ticket\ndescription: Capture.\n---\n\n# Make an issue\nname: review\n"
assert(withoutName(source) == withoutName(copy), "a correct copy must match")
local changed = string.gsub(copy, "Capture.", "Capture!", 1)
assert(withoutName(source) ~= withoutName(changed), "one changed body byte must fail")
print("pass")
