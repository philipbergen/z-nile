--!strict
-- The two structural rules c0185 adds for code shared across homes, pure over a require graph (graph.build's `deps`: each
-- file to the files it resolves to, run from a home, so a file of another home starts with "../"). The spec that applies
-- them to a real home is pickman/tests/meta/architecture.spec.luau, which every home runs from its own folder; their
-- cases are z-nile's, on fixture graphs.
local crosshome = {}

local function sorted(deps: { [string]: { string } }): { string }
	local files: { string } = {}
	for file in deps do
		table.insert(files, file)
	end
	table.sort(files)
	return files
end

-- Every Logic file's require that resolves outside the home, as "<file> -> <target>": a require by a relative path or an
-- alias (`@arcade/...`) into another home resolves on disk, which Lune and the graph follow, but not in Roblox, whose
-- instance tree has no such path (c0185 E2). An arcade feature reaches game Logic as a parameter an adapter passes in.
function crosshome.logicOutside(deps: { [string]: { string } }, logic: string): { string }
	local out: { string } = {}
	for _, file in sorted(deps) do
		if string.sub(file, 1, #logic + 1) == logic .. "/" then
			for _, dep in deps[file] do
				if string.sub(dep, 1, 3) == "../" then
					table.insert(out, `{file} -> {dep}`)
				end
			end
		end
	end
	return out
end

-- Every file but the home's own re-export (`wrapper`) that requires the shared place harness (`shared`) directly, as
-- "<file> -> <shared>": the selector names a home's place specs by the re-export in their closure, so a spec that skips it
-- would not be selected when the home's place changes.
function crosshome.placeBypass(deps: { [string]: { string } }, shared: string, wrapper: string): { string }
	local out: { string } = {}
	for _, file in sorted(deps) do
		if file ~= wrapper and table.find(deps[file], shared) ~= nil then
			table.insert(out, `{file} -> {shared}`)
		end
	end
	return out
end

return crosshome
