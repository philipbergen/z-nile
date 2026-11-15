--!strict
-- c0325: which models wrote the text a review judges, and how sure the tool is. Pure: the rows, the live author, the
-- role's first choices and the known models come in, an answer goes out. The edge that reads them is authorread.
local ledger = require("./ledger")
local models = require("./models")

local authorship = {}

export type Provenance = "recorded" | "assumed" | "unknown"
export type Writer = { model: string, step: string }
export type Authorship = { writers: { Writer }, provenance: Provenance, via: string }
export type Input = {
	live: string?, -- the model that is starting the review (a record or an env id)
	rows: { [string]: { ledger.Row } }, -- step -> the rows read from the item folders
	authorModel: string?, -- Resolved.authorModel of the challenge role (the idea path: the real writer)
	firstChoice: { [string]: string? }, -- step -> the writing role's first-choice model
	known: { string }, -- every model of every role and fallback of the loaded toml
}

-- review mode -> the steps whose writers it judges
authorship.STEPS = {
	idea = { "idea" },
	design = { "design" },
	raft = { "raft" },
	code = { "build" },
	stream = { "build" },
	final = { "idea", "design", "build" },
} :: { [string]: { string } }

-- step -> the role that writes it
authorship.ROLES = {
	idea = "idea",
	design = "design",
	raft = "raft",
	build = "implementation",
} :: { [string]: string }

local PHASE = { idea = "idea", design = "prep", raft = "prep", build = "build" } :: { [string]: string }

local function mine(step: string, row: ledger.Row): boolean
	if row.phase ~= PHASE[step] or row.model == nil or row.model == "" then
		return false
	end
	-- an idea row is the attempt that ended ok (subject `<id> ok`), not the challenge's rows
	return step ~= "idea" or string.sub(row.subject, -3) == " ok"
end

local function filled(s: string?): boolean
	return s ~= nil and s ~= ""
end

function authorship.of(mode: string, inp: Input): Authorship
	local steps = authorship.STEPS[mode]
	if steps == nil then
		error(`authorship: {mode} is not a review mode`, 0)
	end
	local writers: { Writer } = {}
	local vias: { string } = {}
	local provenance: Provenance = "recorded"
	for i, step in steps do
		local models_: { string } = {}
		local via: string
		local sure = true
		if i == 1 and filled(inp.live) then
			models_ = { models.modelOf(inp.live :: string, inp.known) }
			via = "live"
		else
			local list: { ledger.Row } = inp.rows[step] or {}
			for _, row in list do
				if mine(step, row) then
					local m = models.modelOf(row.model :: string, inp.known)
					if not table.find(models_, m) then
						table.insert(models_, m)
					end
				end
			end
			via = "row"
			if #models_ == 0 then
				sure = false
				if filled(inp.authorModel) then
					models_ = { models.modelOf(inp.authorModel :: string, inp.known) }
					via = "authorModel"
				elseif filled(inp.firstChoice[step]) then
					models_ = { models.bareModel(inp.firstChoice[step] :: string) }
					via = "role"
				else
					via = "none"
				end
			end
		end
		for _, m in models_ do
			table.insert(writers, { model = m, step = step })
		end
		if not table.find(vias, via) then
			table.insert(vias, via)
		end
		if #models_ == 0 then
			provenance = "unknown"
		elseif not sure and provenance ~= "unknown" then
			provenance = "assumed"
		end
	end
	return { writers = writers, provenance = provenance, via = table.concat(vias, ",") }
end

-- Whether the challenger try runs a model that wrote the text. Both sides are normalised with bareModel, effort ignored.
function authorship.isAuthor(spec: models.Spec, a: Authorship): boolean
	local mine_ = models.bareModel(spec.model)
	for _, w in a.writers do
		if models.bareModel(w.model) == mine_ then
			return true
		end
	end
	return false
end

return authorship
