--!strict
-- f0420: `./zn work graph <R>`: a named raft and every unit it waits on, band 0 first, each band most-unblocking first,
-- then what can be worked now and what is owed. Pure over work.walk (the same walk `work next <R>` takes its answer from).
-- It reads nothing: the caller has made the Input (workread.collect) and says which CLIs could take a unit.
local depgraph = require("./depgraph")
local work = require("./work")

local workgraph = {}

-- The config name of the activity an action is (f0420's table); "none" for the mechanical ones.
local CONFIG: { [string]: string } = {
	draft = "design",
	rafting = "raft",
	fix = "code",
	implement = "code",
	finish = "code",
	review = "code-review",
	trace = "code",
	["final-review"] = "final",
}

local function pad(text: string, width: number): string
	return text .. string.rep(" ", math.max(0, width - #text))
end

local function levelOf(input: work.Input, id: string): string
	for _, r in input.rafts do
		if r.id == id then
			return r.level or "normal"
		end
	end
	for _, i in (input.issues or {}) :: { work.IssueFact } do
		if i.id == id then
			return i.level or "normal"
		end
	end
	return "normal"
end

local function count(n: number, noun: string): string
	return `{n} {noun}{if n == 1 then "" else "s"}`
end

-- `clis`: the CLIs that can take what `now:` lists. Empty: any (every CLI is taken to do everything for now).
function workgraph.render(input: work.Input, w: work.Walk, clis: { string }?): string
	local bands = depgraph.bands(w.units)
	local waitsOn: { [string]: { string } } = {}
	for _, u in w.units do
		waitsOn[u.id] = u.waitsOn
	end
	-- each band, most unblocking first
	local sorted: { string } = {}
	local top = 0
	for _, b in bands do
		top = math.max(top, b)
	end
	for n = 0, top do
		local inBand: { string } = {}
		for _, id in w.closure do
			if bands[id] == n then
				table.insert(inBand, id)
			end
		end
		for _, id in depgraph.order(inBand, w.unblocks) do
			table.insert(sorted, id)
		end
	end
	local lines: { string } = {}
	local actable = 0
	for _, id in w.closure do
		if w.answers[id].kind == "act" then
			actable += 1
		end
	end
	table.insert(lines, `{w.target} needs {count(#w.closure, "unit")}; {actable} can be worked now`)
	for _, id in sorted do
		local a = w.answers[id]
		local head = `band {bands[id]}  {id}  `
		local unblocks = `unblocks {w.unblocks[id] or 0}`
		if a.kind == "act" then
			local d = a.decision :: work.Decision
			local cfg = CONFIG[d.action]
			local model = if cfg then `{cfg}/{levelOf(input, id)}` else "none"
			local holder = (input.claims or {})[id]
			local note = if holder
				then `held by {holder}{if d.layer ~= "" then "  layer " .. d.layer else ""}`
				else unblocks
			table.insert(lines, head .. pad(d.action, 14) .. pad(model, 21) .. note)
		elseif a.kind == "owed" then
			local items: { string } = {}
			for _, item in a.owed do
				table.insert(items, (string.gsub(item, ` %({id}%)$`, "")))
			end
			table.insert(lines, head .. pad("owed", 14) .. pad(table.concat(items, "; "), 21) .. unblocks)
		elseif a.kind == "waits" then
			table.insert(lines, head .. `waits on {table.concat(waitsOn[id], ", ")}`)
		else
			table.insert(lines, head .. pad("none", 14) .. a.why)
		end
	end
	local now: { string } = {}
	for _, id in w.workable do
		table.insert(now, id)
	end
	local who = if clis and #clis > 0 then `{table.concat(clis, ", ")} can` else "any CLI can"
	table.insert(lines, if #now > 0 then `now: {table.concat(now, ", ")} ({who})` else "now: nothing")
	local owed = work.owedOf(w)
	local own = w.answers[w.target]
	if own and own.questions then
		table.insert(owed, 1, own.owed[1])
	end
	if #owed > 0 then
		table.insert(lines, `owed: {table.concat(owed, "; ")}`)
	end
	return table.concat(lines, "\n")
end

function workgraph.of(input: work.Input, target: string, clis: { string }?): string
	for _, r in input.rafts do
		if r.id == target then
			if r.where == "done" then
				return `{target} has landed: nothing to deliver`
			end
			return workgraph.render(input, work.walk(input, target), clis)
		end
	end
	return `{target} is not in the tracker`
end

return workgraph
