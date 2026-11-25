--!strict
-- f0449: which defects count as rework. STUB for the red run: counts every defect, as before.
local rework = {}

export type Defect = { id: string, created: string?, fixes: { string } }
export type Verdict = { id: string, class: "shipped" | "open" | "unrecorded", fixes: { string } }
export type Row = { id: string, type: string, added: number, minutes: number }

function rework.fixesOf(_front: { [string]: string }): { string }
	return {}
end

function rework.doneDays(_closed: { [string]: string }, _doneAt: { [string]: number }): { [string]: string }
	return {}
end

function rework.classify(defects: { Defect }, _doneDay: { [string]: string }?): { Verdict }
	local out: { Verdict } = {}
	for _, d in defects do
		table.insert(out, { id = d.id, class = "shipped", fixes = d.fixes })
	end
	return out
end

function rework.lines(_rows: { Row }, _verdicts: { Verdict }, _historyKnown: boolean): { string }
	return {}
end

return rework
