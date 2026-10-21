--!strict
-- c0120 AC2: pickman's files live in pickman/: its src/, its Rojo projects, its game spec tiers and test helpers, its
-- Roblox publishing scripts, its promoted specs (by the project of their item) and its tracker items and documents in
-- pickman/.tracker/. Nothing of it is left at the old places; tracker/ keeps only the counter's tombstone. The home has
-- its own .luaurc and the entry points its sequestered check.sh files name (tests/run, scripts/tracker.sh,
-- scripts/check.sh), each one command onto the root's.
local audit = require("@znile/engine/audit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- old place -> pickman/<old place>, for everything the move takes
local MOVED = {
	"src",
	"default.project.json",
	"lobby.project.json",
	"tests/unit",
	"tests/contract",
	"tests/integration",
	"tests/scenario",
	"tests/place",
	"tests/runtime",
	"tests/fixtures/sim",
	"tests/lib/place.luau",
	"tests/lib/sim.luau",
	"tests/lib/fakeengine.luau",
	"scripts/deploy-beta.luau",
	"scripts/runtime-test.luau",
	"scripts/lib/beta.luau",
	"scripts/lib/opencloud.luau",
}
-- what stays at the root: the shared runner and harness, the tooling's specs and fixtures
local STAY = {
	"tests/run.luau",
	"tests/lib/t.luau",
	"tests/lib/fence.luau",
	"tests/lib/fixture.luau",
	"tests/lib/renamed.luau",
	"tests/tooling",
	"tests/fixtures/graph",
	"tests/meta/architecture.spec.luau",
}

local function exists(path: string): boolean
	return fs.isFile(path) or fs.isDir(path)
end

local function lines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

local function tracked(path: string): { string }
	local r = process.exec("git", { "ls-files", "--", path })
	t.expect(r.ok).toBe(true)
	return lines(r.stdout)
end

-- the one command of a shell forwarder: its lines that are neither blank, a comment nor the shebang
local function commands(path: string): { string }
	local out: { string } = {}
	for _, line in lines(fs.readFile(path)) do
		if not string.match(line, "^%s*#") and string.match(line, "%S") then
			table.insert(out, line)
		end
	end
	return out
end

local function run(args: { string }): string
	local r = process.exec("bash", args)
	if not r.ok then
		error(`bash {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`)
	end
	return r.stdout
end

return t.spec("c0120 pickman lives in pickman/", function(it)
	it("every moved path is in pickman/, tracked, and gone from its old place", function()
		local bad: { string } = {}
		for _, p in MOVED do
			if #tracked(`pickman/{p}`) == 0 then
				table.insert(bad, `pickman/{p} is not tracked`)
			end
			if exists(p) or #tracked(p) > 0 then
				table.insert(bad, `{p} is still at the root`)
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("the shared runner, harness and the tooling's specs stay at the root", function()
		for _, p in STAY do
			t.expect(#tracked(p) > 0).toBe(true)
		end
		-- pickman's own meta spec beside the root's
		t.expect(#tracked("pickman/tests/meta/architecture.spec.luau")).toBe(1)
	end)

	it(
		"pickman's tracker items and documents are in pickman/.tracker; tracker/ holds only the tombstone",
		function()
			t.expect(tracked("tracker")).toEqual({ "tracker/next" })
			t.expect(#tracked("pickman/.tracker/architecture.md")).toBe(1)
			t.expect(#tracked("pickman/.tracker/game-design.md")).toBe(1)
			local n = 0
			for _, f in audit.scan(".") do
				if string.sub(f.path, 1, 17) == "pickman/.tracker/" then
					n += 1
				end
			end
			t.expect(n >= 60).toBe(true) -- 43 issues and 20 rafts moved (c0114's classification), and any since
		end
	)

	it("every promoted spec folder is in its item's project's home", function()
		local where: { [string]: string } = {}
		for _, f in audit.scan(".") do
			where[f.id] = f.path
		end
		local bad: { string } = {}
		local counts = { pickman = 0, root = 0 }
		for _, pair in
			{
				{ "pickman/tests/acceptance", "pickman/.tracker/" },
				{ "tests/acceptance", "z-nile/.tracker/" },
			}
		do
			for _, id in fs.readDir(pair[1]) do
				local path = where[id]
				if path and string.sub(path, 1, #pair[2]) ~= pair[2] then
					table.insert(bad, `{pair[1]}/{id}: the item is at {path}`)
				elseif path then
					local key = if pair[1] == "tests/acceptance" then "root" else "pickman"
					counts[key] += 1
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
		t.expect(counts.pickman >= 31).toBe(true) -- the 31 folders of pickman's items promoted before the move
		t.expect(counts.root >= 40).toBe(true)
	end)

	it("pickman/.luaurc points tests, logic, shared and scripts at pickman's folders", function()
		local cfg = serde.decode("json", fs.readFile("pickman/.luaurc")) :: any
		t.expect(cfg.aliases.tests).toBe("./tests")
		t.expect(cfg.aliases.logic).toBe("./src/shared/Logic")
		t.expect(cfg.aliases.shared).toBe("./src/shared")
		t.expect(cfg.aliases.scripts).toBe("./scripts")
		t.expect(cfg.languageMode).toBe("strict")
		-- the root keeps logic and shared, pointed into pickman/src: an alias a worktree's root left undefined would
		-- resolve through the main checkout's .luaurc (worktrees lie inside it)
		local rootCfg = serde.decode("json", fs.readFile(".luaurc")) :: any
		t.expect(rootCfg.aliases.logic).toBe("./pickman/src/shared/Logic")
		t.expect(rootCfg.aliases.shared).toBe("./pickman/src/shared")
	end)

	it("the home's runner is the root's, and its t and renamed are the root's modules", function()
		local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)
		local runner = fs.readFile("pickman/tests/run.luau")
		t.expect(string.find(runner, `return {R}("../../tests/run")`, 1, true) ~= nil).toBe(true)
		for _, m in { "t", "renamed" } do
			local text = fs.readFile(`pickman/tests/lib/{m}.luau`)
			t.expect(string.find(text, `{R}("../../../tests/lib/{m}")`, 1, true) ~= nil).toBe(true)
		end
	end)

	it("the home's forwarders are one command each, executable, and give the root's output", function()
		t.expect(commands("pickman/scripts/tracker.sh"))
			.toEqual({ 'exec bash "$(dirname "$0")/../../zn" "$@"' })
		t.expect(commands("pickman/scripts/check.sh"))
			.toEqual({ 'exec bash "$(dirname "$0")/../../z-nile/check.sh" "$@"' })
		t.expect(commands("pickman/check.sh")).toEqual({
			'exec bash "$(dirname "$0")/../z-nile/check.sh" --project pickman "$@"',
		})
		for _, f in { "pickman/scripts/tracker.sh", "pickman/scripts/check.sh", "pickman/check.sh" } do
			t.expect(process.exec("test", { "-x", f }).ok).toBe(true)
		end
		t.expect(run({ "pickman/scripts/tracker.sh", "audit" })).toBe(run({ "zn", "audit" }))
		t.expect(run({ "pickman/check.sh", "--plan" }))
			.toBe(run({ "z-nile/check.sh", "--plan", "--project", "pickman" }))
		t.expect(run({ "pickman/scripts/check.sh", "--plan" })).toBe(run({ "z-nile/check.sh", "--plan" }))
	end)
end)
