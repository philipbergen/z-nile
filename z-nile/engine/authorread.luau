--!strict
-- c0325: the edge of authorship. Reads the item folders' spend.d (costrow.readMeasured, the one reader of the
-- format) and the role's first choices, and hands them with the live author to the pure authorship.of.
local authorship = require("./authorship")
local costrow = require("./costrow")
local ledger = require("./ledger")
local models = require("./models")

local authorread = {}

-- `dirs` are the item folders of the mode in the checkout the review starts from (design and idea: the issue; raft:
-- the raft's members, where its `raft-prep` rows land; code: each member; stream: the stream's issue; final: each member), `layers` the loaded .models.toml walk.
function authorread.read(
	mode: string,
	dirs: { string },
	layers: { models.Layer },
	live: string?,
	authorModel: string?
): authorship.Authorship
	local steps = authorship.STEPS[mode]
	if steps == nil then
		error(`authorread: {mode} is not a review mode`, 0)
	end
	local all: { ledger.Row } = {}
	for _, dir in dirs do
		for _, row in costrow.readMeasured(dir) do
			table.insert(all, row)
		end
	end
	local rows: { [string]: { ledger.Row } } = {}
	local firstChoice: { [string]: string? } = {}
	for _, step in steps do
		rows[step] = all
		local ok, role = pcall(models.resolveRole, layers, authorship.ROLES[step])
		if ok then
			local resolved = role :: models.Resolved
			firstChoice[step] = resolved.specs[resolved.order[1]].model
		end
	end
	return authorship.of(mode, {
		live = live,
		rows = rows,
		authorModel = authorModel,
		firstChoice = firstChoice,
		known = models.knownModels(layers),
	})
end

return authorread
