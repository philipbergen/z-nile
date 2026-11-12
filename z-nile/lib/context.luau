--!strict
-- The one reader of a select.Context: each home's watch files. Adapter: reads files. Shared by affected.luau and
-- specs.luau so that selection and fingerprints are made from the same facts. A watch file that does not parse, or
-- that names a missing path, fails the whole read (nil and a reason): the gate fails closed.

local fs = require("@lune/fs")
local graph = require("./graph")
local projects = require("../engine/projects")
local select = require("./select")
local watch = require("./watch")

local context = {}

local EMPTY: graph.Graph = { files = {}, deps = {}, unresolved = {}, dynamic = {} }

-- `graphOnly` is accepted and ignored: the require graph is no longer an input of selection.
function context.build(reg: projects.Registry, _graphOnly: boolean?): (select.Context?, string?)
	local rules = select.rules(reg)
	local watches: { [string]: { string } } = {}
	local problems: { string } = {}
	local reader: watch.Reader = {
		isDir = function(path: string): boolean
			return fs.isDir(path)
		end,
		isFile = function(path: string): boolean
			return fs.isFile(path)
		end,
		readDir = function(path: string): { string }
			return fs.readDir(path)
		end,
		readFile = function(path: string): string
			return fs.readFile(path)
		end,
	}
	for _, h in rules.homes do
		if h.prefix ~= "" then
			local found, why = watch.collect(reader, h.prefix)
			for spec, paths in found do
				watches[spec] = paths
			end
			for _, p in why do
				table.insert(problems, p)
			end
		end
	end
	if #problems > 0 then
		return nil, table.concat(problems, "\n")
	end
	return {
		rules = rules,
		graph = EMPTY,
		inputs = {},
		places = {},
		watches = watches,
		current = {},
	},
		nil
end

return context
