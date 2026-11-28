--!strict
-- f0421 slice 3: the one reader of the model consent record, `z-nile/.tracker/model-consent.md` on main. Each row is a
-- person's answer, given at a terminal (S2's `./zn model --consent <cli>`, under the guard that records an approval), to
-- whether a CLI's highest entries below a level it lacks may stand in for that level, in one kind of work:
--
--   # model consent
--   when<TAB>who<TAB>cli<TAB>kind<TAB>needed<TAB>stand-in<TAB>answer
--   2026-11-24T20:00:00Z<TAB>Philip Bergen<TAB>agy<TAB>review<TAB>ultra<TAB>gemini-4-argon-high,claude-opus-5-5-high<TAB>yes
--
-- `kind` is writing or review, `needed` the level the CLI lacks, `stand-in` the entries that would stand in, as the command
-- computed them, and `answer` yes or no (a no is recorded too). The latest row of a CLI, kind and level is the answer. Pure:
-- text in, rows out. S1a reads and checks the record; nothing acts on it until S2.
local ledger = require("./ledger")
local models = require("./models")

local modelconsent = {}

modelconsent.FILE = "z-nile/.tracker/model-consent.md"
modelconsent.TITLE = "# model consent"
modelconsent.HEADER = { "when", "who", "cli", "kind", "needed", "stand-in", "answer" }

export type Row = {
	when: string,
	who: string,
	cli: string,
	kind: string,
	needed: string,
	standIn: { string },
	answer: string,
	line: number,
}

-- The rows of the record at `path`, in order. An empty text is no record yet. Every refusal names the file, the line and the
-- rule.
function modelconsent.parse(text: string, path: string): { Row }
	local rows: { Row } = {}
	if text == "" then
		return rows
	end
	local lines = string.split(text, "\n")
	if lines[1] ~= modelconsent.TITLE then
		error(`{path}: line 1 is not {modelconsent.TITLE}`, 0)
	end
	if lines[2] ~= table.concat(modelconsent.HEADER, "\t") then
		error(`{path}: line 2 is not the header ({table.concat(modelconsent.HEADER, ", ")})`, 0)
	end
	for i = 3, #lines do
		local line = lines[i]
		if line ~= "" then
			local c = string.split(line, "\t")
			if #c ~= #modelconsent.HEADER then
				error(`{path}: line {i} has {#c} fields, not {#modelconsent.HEADER}`, 0)
			end
			local at = `{path}: line {i}`
			if string.match(c[1], "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") == nil then
				error(`{at}: when is {c[1]}, not a UTC time (2026-11-24T20:00:00Z)`, 0)
			end
			if c[2] == "" then
				error(`{at}: who is empty`, 0)
			end
			if table.find(models.CLIS, c[3]) == nil then
				error(`{at}: cli is {c[3]}, not a supported CLI ({table.concat(models.CLIS, ", ")})`, 0)
			end
			if c[4] ~= "writing" and c[4] ~= "review" then
				error(`{at}: kind is {c[4]}: writing or review`, 0)
			end
			if table.find(models.ALIASES, c[5]) == nil then
				error(`{at}: needed is {c[5]}, not a level ({table.concat(models.ALIASES, ", ")})`, 0)
			end
			if c[6] == "" then
				error(`{at}: stand-in names no model`, 0)
			end
			local standIn: { string } = {}
			for _, id in string.split(c[6], ",") do
				if not ledger.isModel(id) then
					error(`{at}: stand-in names {id}, which is not a model id`, 0)
				end
				table.insert(standIn, id)
			end
			if c[7] ~= "yes" and c[7] ~= "no" then
				error(`{at}: answer is {c[7]}: yes or no`, 0)
			end
			table.insert(rows, {
				when = c[1],
				who = c[2],
				cli = c[3],
				kind = c[4],
				needed = c[5],
				standIn = standIn,
				answer = c[7],
				line = i,
			})
		end
	end
	return rows
end

-- The latest row for a CLI, a kind and a needed level, or nil when the person was never asked.
function modelconsent.latest(rows: { Row }, cli: string, kind: string, needed: string): Row?
	local found: Row? = nil
	for _, row in rows do
		if row.cli == cli and row.kind == kind and row.needed == needed then
			found = row
		end
	end
	return found
end

return modelconsent
