--!strict
-- c0244 AC1: the bounded-command seatbelt takes every registered home's runner from the registry, not from a hand
-- list that stops at pickman (R0075 review 001 F1). Pure cases over `Context.homes`, and the hook end to end.
local boundcmd = require("@znile/engine/boundcmd")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function refused(command: string, ctx: boundcmd.Context?): boolean
	local v = boundcmd.check(command, ctx)
	return (not v.ok) and v.rule == "unbounded"
end

local function hook(command: string, checkout: string, cwd: string?)
	local payload = serde.encode(
		"json",
		{ tool_name = "Bash", cwd = cwd or checkout, tool_input = { command = command } }
	)
	return process.exec(
		"lune",
		{ "run", `{ROOT}/z-nile/guard-bash` },
		{ cwd = ROOT, env = { ZN_CHECKOUT = checkout }, stdio = { stdin = payload } }
	)
end

return t.spec("c0244 the seatbelt knows every registered home's runner", function(it)
	it("AC1: a registered home's runner is the gate's own tooling", function()
		local ctx: boundcmd.Context = { homes = { "snake", "arcade" } }
		t.expect(refused("lune run snake/tests/run", ctx)).toBe(false)
		t.expect(refused("lune run arcade/tests/run -- tests/meta/home.spec.luau", ctx)).toBe(false)
	end)

	it("AC1: only the registry's homes count: a folder it does not list is refused", function()
		local ctx: boundcmd.Context = { homes = { "snake" } }
		t.expect(refused("lune run portal/tests/run", ctx)).toBe(true)
		t.expect(refused("lune run nowhere/tests/run", ctx)).toBe(true)
	end)

	it("AC1: a home name that is not a plain folder adds nothing", function()
		local ctx: boundcmd.Context = { homes = { "..", ".", "a/b", "", "../x" } }
		t.expect(refused("lune run ../x/tests/run", ctx)).toBe(true)
		t.expect(refused("lune run a/b/tests/run", ctx)).toBe(true)
	end)

	it("AC1: today's entries stay, with homes or without", function()
		for _, ctx in { {} :: boundcmd.Context, { homes = { "snake" } } :: boundcmd.Context } do
			t.expect(refused("lune run tests/run", ctx)).toBe(false)
			t.expect(refused("lune run z-nile/tests/run", ctx)).toBe(false)
			t.expect(refused("lune run pickman/tests/run", ctx)).toBe(false)
		end
		t.expect(refused("lune run snake/tests/run", {})).toBe(true)
	end)

	it("AC1: an absolute runner path under the checkout counts for a registered home", function()
		local ctx: boundcmd.Context = { homes = { "snake" }, checkout = ROOT }
		t.expect(refused(`lune run {ROOT}/snake/tests/run`, ctx)).toBe(false)
		t.expect(refused("lune run /tmp/other/snake/tests/run", ctx)).toBe(true)
	end)

	it(
		"AC1: the hook reads the registry of its checkout and lets a registered home's runner through",
		function()
			t.expect(hook("lune run snake/tests/run", ROOT).code).toBe(0)
			t.expect(hook("lune run nowhere/tests/run", ROOT).code).toBe(2)
		end
	)

	it(
		"AC1: the hook takes its homes from the registry it is pointed at, not from a list of names",
		function()
			-- a fixture checkout whose registry names one project, `zz`: its runner passes, a real home's does not
			local dir = `{ROOT}/z-nile/.cache/c0244-own-registry`
			fs.writeDir(`{dir}/z-nile`)
			fs.writeFile(
				`{dir}/z-nile/projects.toml`,
				'retired = []\n\n[[project]]\nname = "zz"\nroot = "zz/.tracker"\n'
			)
			local zz = hook("lune run zz/tests/run", dir).code
			local snake = hook("lune run snake/tests/run", dir).code
			fs.removeDir(dir)
			t.expect(zz).toBe(0)
			t.expect(snake).toBe(2)
		end
	)

	it("AC1: the registry is read from ZN_CHECKOUT, whatever folder the call runs in", function()
		-- from pickman/, `../snake/tests/run` is the registered home's runner; from a folder outside the checkout it is not
		t.expect(hook("lune run ../snake/tests/run", ROOT, `{ROOT}/pickman`).code).toBe(0)
		t.expect(hook("lune run snake/tests/run", ROOT, "/tmp").code).toBe(2)
	end)

	it("AC1: a checkout whose registry cannot be read keeps today's list", function()
		-- a fixture checkout under the home's .cache with no z-nile/projects.toml
		local dir = `{ROOT}/z-nile/.cache/c0244-no-registry`
		fs.writeDir(dir)
		local pickman = hook("lune run pickman/tests/run", dir).code
		local snake = hook("lune run snake/tests/run", dir).code
		fs.removeDir(dir)
		t.expect(pickman).toBe(0)
		t.expect(snake).toBe(2)
	end)
end)
