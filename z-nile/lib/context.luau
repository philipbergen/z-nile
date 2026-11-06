--!strict
-- The one reader of a select.Context (c0165): the graph of every home, each home's tests/inputs.tsv (absent: empty) and
-- each home's place inputs (c0185). Adapter: reads files. Shared by affected.luau and specs.luau so that selection and
-- fingerprints are made from the same facts. Any unreadable piece fails the whole read (nil and a reason): the gate
-- fails closed.

local fs = require("@lune/fs")
local graph = require("./graph")
local projects = require("../engine/projects")
local select = require("./select")

local context = {}

-- `graphOnly`: read no inputs.tsv (the selector's old behaviour, which the promoted selector specs pin).
function context.build(reg: projects.Registry, graphOnly: boolean?): (select.Context?, string?)
	local rules = select.rules(reg)
	local inputs: select.Inputs = {}
	local places: { [string]: { string } } = {}
	local okAll, err = pcall(function()
		for _, h in rules.homes do
			if h.prefix ~= "" then
				places[h.prefix] = graph.placeInputs(h.prefix)
			end
		end
	end)
	if not okAll then
		return nil, tostring(err)
	end
	if not graphOnly then
		for _, h in rules.homes do
			local file = `{h.prefix}tests/inputs.tsv`
			if h.prefix ~= "" and fs.isFile(file) then
				local parsed, why = select.parseInputs(fs.readFile(file), h.prefix, rules.roots)
				if parsed == nil then
					return nil, `{file}: {why}`
				end
				for spec, list in parsed do
					inputs[spec] = list
				end
			end
		end
	end
	return { rules = rules, graph = graph.build(select.graphRoots(rules)), inputs = inputs, places = places },
		nil
end

return context
