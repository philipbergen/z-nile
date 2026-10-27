--!strict
-- Structural rules from the `pickman-arch` and `pickman-test` skills, enforced mechanically: pickman's (c0120), run from
-- pickman/ like every pickman spec. The tooling's own rules are in the root's tests/meta/architecture.spec.luau.
local depsReader = require("@znile/lib/deps")
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local t = require("@tests/lib/t")

local LOGIC = "src/shared/Logic"

local function features(): { string }
	local out: { string } = {}
	if fs.isDir(LOGIC) then
		for _, name in fs.readDir(LOGIC) do
			if fs.isDir(`{LOGIC}/{name}`) then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

local function featureOf(file: string): string?
	return string.match(file, "^src/shared/Logic/([^/]+)/")
end

-- The declared graph, through the one deps reader (c0163): it fails closed, so a conflict marker or a stray line in
-- the block fails here, naming the line, instead of being skipped.
local function declaredDeps(): { [string]: { [string]: boolean } }
	local declared, problems =
		depsReader.parse(fs.readFile(".tracker/architecture.md"), ".tracker/architecture.md")
	if #problems > 0 then
		error(table.concat(problems, "\n"), 0)
	end
	return declared
end

return t.spec("architecture", function(it)
	local g = graph.build({ "src", "tests" })

	it("every require resolves", function()
		local msgs = {}
		for _, u in g.unresolved do
			table.insert(msgs, `{u.file}: require("{u.spec}")`)
		end
		t.expect(table.concat(msgs, "\n")).toBe("")
	end)

	it("src requires use only relative paths, @self/ or @game/ReplicatedStorage/", function()
		local msgs = {}
		for _, v in graph.srcAliasViolations("src") do
			table.insert(msgs, `{v.file}: {v.spec}`)
		end
		t.expect(table.concat(msgs, "\n")).toBe("")
	end)

	it("src has no dynamic requires", function()
		local bad = {}
		for _, f in g.dynamic do
			if string.sub(f, 1, 4) == "src/" then
				table.insert(bad, f)
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("every Luau file is --!strict", function()
		local bad = {}
		-- pickman's own files; its .tracker/ holds tracker documents and specs not yet promoted
		local all = graph.listLuau("src", graph.listLuau("tests", graph.listLuau("scripts")))
		for _, f in all do
			if not string.match(fs.readFile(f), "^%-%-!strict") then
				table.insert(bad, f)
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("Logic never touches the Roblox engine", function()
		local bad = {}
		for _, f in graph.listLuau(LOGIC) do
			local src = fs.readFile(f)
			for _, word in { "game", "workspace", "Instance", "script", "Enum" } do
				if string.find(src, `%f[%w_]{word}%f[^%w_]`) then
					table.insert(bad, `{f}: {word}`)
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("features are only used through their init.luau", function()
		local bad = {}
		for file, deps in g.deps do
			for _, dep in deps do
				local target = featureOf(dep)
				if target and featureOf(file) ~= target and dep ~= `{LOGIC}/{target}/init.luau` then
					table.insert(bad, `{file} -> {dep}`)
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("cross-feature requires are declared in .tracker/architecture.md", function()
		local declared = declaredDeps()
		local bad = {}
		for file, deps in g.deps do
			local from = featureOf(file)
			for _, dep in deps do
				local to = featureOf(dep)
				if from and to and from ~= to and not (declared[from] and declared[from][to]) then
					table.insert(bad, `{from} -> {to} ({file})`)
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("declared feature dependencies have no cycle", function()
		local declared = declaredDeps()
		local state: { [string]: number } = {}
		local cycle: string? = nil
		local function visit(n: string, path: string)
			if state[n] == 1 then
				cycle = path
				return
			end
			if state[n] == 2 or cycle then
				return
			end
			state[n] = 1
			local providers: { [string]: boolean } = declared[n] or {}
			for m in providers do
				visit(m, `{path} -> {m}`)
			end
			state[n] = 2
		end
		for n in declared do
			visit(n, n)
		end
		t.expect(cycle).toBe(nil)
	end)

	it("every feature has unit specs", function()
		local bad = {}
		for _, f in features() do
			if #graph.listLuau(`tests/unit/{f}`) == 0 then
				table.insert(bad, f)
			end
		end
		t.expect(table.concat(bad, ", ")).toBe("")
	end)
end)
