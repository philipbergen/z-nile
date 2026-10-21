--!strict
-- E2: skip tracker/ and tests/acceptance/, then strongest over what remains.
-- Not a toml parser and not the implementation. The spec pins scripts/tracker/models.luau.

type Spec = { model: string, rank: number, maxTokens: number }

local function dirsOf(paths: { string }): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, path in paths do
		local skip = string.sub(path, 1, 8) == "tracker/" or string.sub(path, 1, 17) == "tests/acceptance/"
		if not skip then
			local dir = string.match(path, "^(.*)/[^/]+$") or ""
			if not seen[dir] then
				seen[dir] = true
				table.insert(out, dir)
			end
		end
	end
	if #out == 0 then
		table.insert(out, "")
	end
	return out
end

local function resolve(dir: string): Spec
	local spec: Spec = { model = "grok-4.7", rank = 2, maxTokens = 300000 }
	if dir == "game" or string.sub(dir, 1, 5) == "game/" then
		spec.maxTokens = 1000
	end
	return spec
end

local function strongest(specs: { Spec }): Spec
	local best = specs[1]
	for i = 2, #specs do
		local spec = specs[i]
		if spec.rank > best.rank or (spec.rank == best.rank and spec.maxTokens > best.maxTokens) then
			best = spec
		end
	end
	return best
end

local function cap(paths: { string }): number
	local specs: { Spec } = {}
	for _, dir in dirsOf(paths) do
		table.insert(specs, resolve(dir))
	end
	return strongest(specs).maxTokens
end

local game = { "game/x.luau", "tracker/issues/c0001/acceptance/a.spec.luau" }
local mixed = { "game/x.luau", "tracker/issues/c0001/acceptance/a.spec.luau", "other/y.luau" }
if cap(game) ~= 1000 then
	error(`game issue cap {cap(game)}`)
end
if cap(mixed) ~= 300000 then
	error(`mixed issue cap {cap(mixed)}`)
end

local issues: { [string]: { string } } = { c0001 = game, c0002 = mixed }
local function raftCap(members: { string }): number
	local paths: { string } = {}
	for _, id in members do
		for _, path in issues[id] do
			table.insert(paths, path)
		end
	end
	return cap(paths)
end

if raftCap({ "c0001", "c0002" }) ~= 300000 then
	error("both members")
end
if raftCap({ "c0001" }) ~= 1000 then
	error("game member only")
end
print("pass")
