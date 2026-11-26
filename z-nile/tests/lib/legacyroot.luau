--!strict
-- The repository's root `.models.toml` as the legacy tables only (f0421 step 8): the specs that assert how a legacy walk
-- resolves (the role of each activity, the fallbacks, `./zn model light` answering from the implementation role) read this,
-- not the file itself, so they hold whether or not the root file also carries the new-shape seed beside the legacy tables.
-- The seed starts at the marker line; a file without it is returned whole.
local fs = require("@lune/fs")

local legacyroot = {}

legacyroot.MARKER = "# The new shape (f0421 slice 2, step 8)"

-- `text` without the new-shape tables.
function legacyroot.strip(text: string): string
	local at = string.find(text, legacyroot.MARKER, 1, true)
	if at == nil then
		return text
	end
	return string.sub(text, 1, at - 1)
end

-- The root file at `top` (the checkout), legacy tables only.
function legacyroot.text(top: string): string
	return legacyroot.strip(fs.readFile(`{top}/.models.toml`))
end

return legacyroot
