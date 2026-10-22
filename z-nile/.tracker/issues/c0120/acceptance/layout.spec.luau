--!strict
-- c0120 AC2: pickman's files live in pickman/ (its src/, its Rojo projects, its game spec tiers and test helpers, its
-- Roblox publishing scripts, its promoted specs and its tracker items and documents in pickman/.tracker/), and the
-- tooling's tests live in z-nile/tests/ (the shared runner and harness, the tooling specs, their fixtures and z-nile's
-- promoted specs): z-nile/ is its home and the root belongs to no project (decided with the user, 2026-10-21). Nothing
-- is left at the old places: no tests/ at the root, and tracker/ keeps only the counter's tombstone. Each home has its
-- .luaurc and the entry points its sequestered check.sh files name (tests/run, scripts/tracker.sh, scripts/check.sh),
-- each one command; a home's scripts/check.sh runs that project's gate only ("pickman's gate only").
-- These specs run from z-nile/: the checkout is read from its top.
local audit = require("@znile/engine/audit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- old place -> pickman/<old place>
local PICKMAN = {
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
	"tests/meta/architecture.spec.luau",
	"scripts/deploy-beta.luau",
	"scripts/runtime-test.luau",
	"scripts/lib/beta.luau",
	"scripts/lib/opencloud.luau",
}
-- old place -> z-nile/<old place>: the tooling's specs, runner, harness and fixtures
local ZNILE = {
	"tests/run.luau",
	"tests/lib/t.luau",
	"tests/lib/fence.luau",
	"tests/lib/fixture.luau",
	"tests/lib/clone.luau",
	"tests/lib/cleanup.luau",
	"tests/lib/engine.luau",
	"tests/lib/trackerfix.luau",
	"tests/lib/cachepaths.luau",
	"tests/lib/renamed.luau",
	"tests/tooling",
	"tests/fixtures/graph",
	"tests/fixtures/spend",
}

local function exists(rel: string): boolean
	return fs.isFile(`{TOP}/{rel}`) or fs.isDir(`{TOP}/{rel}`)
end

local function lines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

local function tracked(path: string): { string }
	local r = process.exec("git", { "ls-files", "--", path }, { cwd = TOP })
	t.expect(r.ok).toBe(true)
	return lines(r.stdout)
end

-- the one command of a shell forwarder: its lines that are neither blank, a comment nor the shebang
local function commands(rel: string): { string }
	local out: { string } = {}
	for _, line in lines(fs.readFile(`{TOP}/{rel}`)) do
		if not string.match(line, "^%s*#") and string.match(line, "%S") then
			table.insert(out, line)
		end
	end
	return out
end

local function run(args: { string }): string
	local r = process.exec("bash", args, { cwd = TOP })
	if not r.ok then
		error(`bash {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`)
	end
	return r.stdout
end

local function json(rel: string): any
	return serde.decode("json", fs.readFile(`{TOP}/{rel}`))
end

return t.spec("c0120 every project's files live in its home", function(it)
	it("every moved path is in its home, tracked, and gone from its old place", function()
		local bad: { string } = {}
		for _, pair in { { "pickman", PICKMAN }, { "z-nile", ZNILE } } do
			for _, p in pair[2] do
				if #tracked(`{pair[1]}/{p}`) == 0 then
					table.insert(bad, `{pair[1]}/{p} is not tracked`)
				end
				if exists(p) or #tracked(p) > 0 then
					table.insert(bad, `{p} is still at the root`)
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("no tests/ is left at the root, and each home has its own meta spec", function()
		t.expect(#tracked("tests")).toBe(0)
		t.expect(exists("tests")).toBe(false)
		t.expect(#tracked("pickman/tests/meta/architecture.spec.luau")).toBe(1)
		t.expect(#tracked("z-nile/tests/meta/architecture.spec.luau")).toBe(1)
	end)

	it(
		"pickman's tracker items and documents are in pickman/.tracker; tracker/ holds only the tombstone",
		function()
			t.expect(tracked("tracker")).toEqual({ "tracker/next" })
			t.expect(#tracked("pickman/.tracker/architecture.md")).toBe(1)
			t.expect(#tracked("pickman/.tracker/game-design.md")).toBe(1)
			local n = 0
			for _, f in audit.scan(TOP) do
				if string.sub(f.path, 1, 17) == "pickman/.tracker/" then
					n += 1
				end
			end
			t.expect(n > 0).toBe(true)
		end
	)

	it("every promoted spec folder is in its item's project's home", function()
		local where: { [string]: string } = {}
		for _, f in audit.scan(TOP) do
			where[f.id] = f.path
		end
		local bad: { string } = {}
		local counts = { pickman = 0, ["z-nile"] = 0 }
		for _, home in { "pickman", "z-nile" } do
			for _, id in fs.readDir(`{TOP}/{home}/tests/acceptance`) do
				local path = where[id]
				if path and string.sub(path, 1, #home + 10) ~= `{home}/.tracker/` then
					table.insert(bad, `{home}/tests/acceptance/{id}: the item is at {path}`)
				elseif path then
					counts[home] += 1
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
		t.expect(counts.pickman > 0).toBe(true)
		t.expect(counts["z-nile"] > 0).toBe(true)
	end)

	it(
		"each home's .luaurc points its aliases at its own folders; the root keeps every alias, pointed into them",
		function()
			local cfg = json("pickman/.luaurc")
			t.expect(cfg.aliases.tests).toBe("./tests")
			t.expect(cfg.aliases.logic).toBe("./src/shared/Logic")
			t.expect(cfg.aliases.shared).toBe("./src/shared")
			t.expect(cfg.aliases.scripts).toBe("./scripts")
			t.expect(cfg.languageMode).toBe("strict")
			local z = json("z-nile/.luaurc")
			t.expect(z.aliases.tests).toBe("./tests")
			t.expect(z.languageMode).toBe("strict")
			-- an alias a worktree's own .luaurc chain left undefined would resolve through the main checkout's .luaurc
			-- (worktrees lie inside it), so the root defines every one, pointed into its project (Guesses 8 and 15)
			local rootCfg = json(".luaurc")
			t.expect(rootCfg.aliases.logic).toBe("./pickman/src/shared/Logic")
			t.expect(rootCfg.aliases.shared).toBe("./pickman/src/shared")
			t.expect(rootCfg.aliases.tests).toBe("./z-nile/tests")
			t.expect(rootCfg.aliases.znile).toBe("./z-nile")
			t.expect(rootCfg.aliases.scripts).toBe("./scripts")
		end
	)

	-- a finished check.sh that formats and lints its specs runs stylua and selene from its home, where they look for
	-- their configuration
	-- (found by running the finished checks by hand: c0047, c0048, c0050)
	it("each home carries the root's stylua.toml and selene.toml, unchanged", function()
		for _, file in { "stylua.toml", "selene.toml" } do
			local root = fs.readFile(`{TOP}/{file}`)
			for _, home in { "pickman", "z-nile" } do
				t.expect(exists(`{home}/{file}`) and fs.readFile(`{TOP}/{home}/{file}`) == root).toBe(true)
			end
		end
	end)

	it("pickman's runner is z-nile's, and its t and renamed are z-nile's modules", function()
		local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)
		local runner = fs.readFile(`{TOP}/pickman/tests/run.luau`)
		t.expect(string.find(runner, `return {R}("../../z-nile/tests/run")`, 1, true) ~= nil).toBe(true)
		for _, m in { "t", "renamed" } do
			local text = fs.readFile(`{TOP}/pickman/tests/lib/{m}.luau`)
			t.expect(string.find(text, `{R}("../../../z-nile/tests/lib/{m}")`, 1, true) ~= nil).toBe(true)
		end
	end)

	it(
		"each home's forwarders are one command each, executable; scripts/check.sh is the project's own gate",
		function()
			for _, home in { "pickman", "z-nile" } do
				t.expect(commands(`{home}/scripts/tracker.sh`))
					.toEqual({ 'exec bash "$(dirname "$0")/../../zn" "$@"' })
			end
			t.expect(commands("pickman/scripts/check.sh"))
				.toEqual({ 'exec bash "$(dirname "$0")/../check.sh" "$@"' })
			t.expect(commands("pickman/check.sh")).toEqual({
				'exec bash "$(dirname "$0")/../z-nile/check.sh" --project pickman "$@"',
			})
			t.expect(commands("z-nile/scripts/check.sh")).toEqual({
				'exec bash "$(dirname "$0")/../check.sh" --project z-nile "$@"',
			})
			for _, f in
				{
					"pickman/scripts/tracker.sh",
					"pickman/scripts/check.sh",
					"pickman/check.sh",
					"z-nile/scripts/tracker.sh",
					"z-nile/scripts/check.sh",
				}
			do
				t.expect(process.exec("test", { "-x", `{TOP}/{f}` }).ok).toBe(true)
			end
			t.expect(run({ "pickman/scripts/tracker.sh", "audit" })).toBe(run({ "zn", "audit" }))
			t.expect(run({ "z-nile/scripts/tracker.sh", "audit" })).toBe(run({ "zn", "audit" }))
			-- the check forwarders are pinned by their one command above: running them here would run a gate in the
			-- checkout from a spec (gate-homes runs them with --plan in a copy)
		end
	)
end)
