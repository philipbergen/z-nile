--!strict
-- f0421: who wrote the text a review reads, and the note a review on that model leaves in its record. A review on the writer's
-- own model is allowed, not preferred (owner, 2026-11-24), and whoever records it (`./zn spend`, `./zn commit`, a dispatched
-- review, `./zn idea`) says so with this one note. The writers are the `model` of the item's spend rows in the writer's phase
-- (spend's one reader); a raft's build rows are its members'.
local models = require("./models")
local spend = require("./spend")
local store = require("./store")

local reviewrec = {}

-- the spend phase of the activity that wrote what a review reads (design and raft reviews read the prep rows, a code or final
-- review the build rows); nil for an activity that reviews nothing
reviewrec.WRITER_PHASE = {
	["design-review"] = "prep",
	["raft-review"] = "prep",
	["code-review"] = "build",
	["final-review"] = "build",
} :: { [string]: string }

-- The models of the spend rows of `item` in `phase`, each once, read from the item's folder under `cwd`. When none is known,
-- the models are empty and the second value says why (one wording whoever asks).
function reviewrec.spendWriters(item: store.Item, phase: string, cwd: string): ({ string }, string?)
	local found: { string } = {}
	local ok, got = pcall(function(): { string }
		local owners: { store.Item } = { item }
		if item.kind == "raft" and phase == "build" then
			owners = store.members(item.id)
		end
		local seen: { string } = {}
		for _, owner in owners do
			for _, row in spend.rowsIn(`{cwd}/{owner.dir}`) do
				if row.phase == phase and row.model ~= nil and row.model ~= "" then
					table.insert(seen, row.model)
				end
			end
		end
		return seen
	end)
	if not ok then
		return found, `the spend rows of {item.id} could not be read ({tostring(got)})`
	end
	for _, model in got :: { string } do
		if not table.find(found, model) then
			table.insert(found, model)
		end
	end
	if #found == 0 then
		return found, `{item.id} has no {phase} spend row with a model`
	end
	return found, nil
end

-- The writer whose model is `model` (effort and case ignored: models.sameModel), the first that matches, or nil.
function reviewrec.matched(model: string, writers: { string }): string?
	for _, writer in writers do
		if models.sameModel(model, writer) then
			return writer
		end
	end
	return nil
end

-- The note a record carries when the review ran on the model `writer` that wrote the text.
function reviewrec.note(writer: string): string
	return `(same-model: reviewed on {writer}'s model, which wrote the text)`
end

-- The note for a review recorded on `model` of the text of `item`, or nil (another model, or no writer known).
function reviewrec.noteFor(item: store.Item, phase: string, model: string, cwd: string): string?
	local writers = reviewrec.spendWriters(item, phase, cwd)
	local writer = reviewrec.matched(model, writers)
	return if writer ~= nil then reviewrec.note(writer) else nil
end

return reviewrec
