--!strict
-- c0189 AC2: hooks.plan (z-nile/engine/hooks.luau), the pure decision behind `./zn hooks` and `./zn hooks --check`: from
-- the reference hook text (origin/main's copy, or the tree's own when there is no origin/main), what is at the hook's
-- place, and the git configuration that moves the hooks folder, it says whether the copy is fine, to be written, to be
-- left to a person, or not there to judge yet, and names each problem and its fix.
local hooks = require("@znile/engine/hooks")
local t = require("@tests/lib/t")

local DEST = "/repo/.git/hooks/reference-transaction"
local SOURCE = "#!/bin/sh\n" .. hooks.MARKER .. "\nexit 0\n"
local NAME = "z-nile/lib/repo-hooks/reference-transaction"

local function state(over: { [string]: any }): hooks.State
	local s: any = {
		dest = DEST,
		from = "origin/main",
		source = SOURCE,
		kind = "file",
		installed = SOURCE,
		executable = true,
		reviewed = false,
		redirects = {},
	}
	for k, v in over do
		s[k] = v
	end
	return s :: hooks.State
end

local function has(list: { string }, needle: string): boolean
	for _, p in list do
		if string.find(p, needle, 1, true) then
			return true
		end
	end
	return false
end

return t.spec("c0189 hooks.plan", function(it)
	it("an executable, exact copy of our own file is ok, with nothing to report", function()
		local p = hooks.plan(state({}))
		t.expect(p.action).toBe("ok")
		t.expect(#p.problems).toBe(0)
	end)

	it("no file at the place is installed, and reported missing", function()
		local p = hooks.plan(state({ kind = "absent", installed = nil, executable = false }))
		t.expect(p.action).toBe("install")
		t.expect(p.problems).toEqual({ `hooks: {DEST} is missing; run ./zn hooks` })
	end)

	it(
		"our own file that differs from the reference is replaced, and reported stale, naming whose copy it is",
		function()
			local p = hooks.plan(state({ installed = SOURCE .. "# older\n" }))
			t.expect(p.action).toBe("install")
			t.expect(#p.problems).toBe(1)
			t.expect(has(p.problems, `differs from origin/main's {NAME}; run ./zn hooks`)).toBe(true)
			local own = hooks.plan(state({ from = "tree", installed = SOURCE .. "# older\n" }))
			t.expect(has(own.problems, `differs from this tree's {NAME}; run ./zn hooks`)).toBe(true)
		end
	)

	it(
		"an older copy that origin/main's history held is updated, and --check may accept it with a note",
		function()
			local p = hooks.plan(state({ installed = SOURCE .. "# older\n", reviewed = true }))
			t.expect(p.action).toBe("install")
			t.expect(p.older).toBe(true)
			t.expect(p.problems).toEqual({
				`hooks: {DEST} is an older reviewed copy of origin/main's {NAME}; run ./zn hooks to update`,
			})
			-- not when it is not executable, nor when the text is one origin/main never held, nor against the tree's own copy
			local noExec =
				hooks.plan(state({ installed = SOURCE .. "# older\n", reviewed = true, executable = false }))
			t.expect(noExec.older).toBe(false)
			t.expect(has(noExec.problems, "differs from")).toBe(true)
			local never = hooks.plan(state({ installed = SOURCE .. "# older\n" }))
			t.expect(never.older).toBe(false)
			t.expect(has(never.problems, "differs from")).toBe(true)
		end
	)

	it("blobIds reads the texts the source has had from git log --raw, and leaves out a deletion", function()
		local a, b, c = string.rep("a", 40), string.rep("b", 40), string.rep("c", 40)
		local zero = string.rep("0", 40)
		local raw = table.concat({
			`:000000 100755 {zero} {a} A\t{NAME}`,
			`:100755 100755 {a} {b} M\t{NAME}`,
			`:100755 000000 {b} {zero} D\t{NAME}`,
			"",
		}, "\n")
		t.expect(hooks.blobIds(raw)).toEqual({ [a] = true, [b] = true })
		t.expect(hooks.blobIds("")).toEqual({})
		t.expect(hooks.blobIds(`:100755 100755 {a} {c} M\t{NAME}\n`)[c]).toBe(true)
	end)

	it("our own exact copy that is not executable is fixed, and reported", function()
		local p = hooks.plan(state({ executable = false }))
		t.expect(p.action).toBe("install")
		t.expect(has(p.problems, "is not executable, so git skips it; run ./zn hooks")).toBe(true)
	end)

	it("a hook without our marker line is never overwritten", function()
		for _, text in
			{
				"#!/bin/sh\nexit 0\n",
				"",
				`#!/bin/sh\n{hooks.MARKER} extra\n`,
				`#!/bin/sh\necho '{hooks.MARKER}'\n`,
			}
		do
			local p = hooks.plan(state({ installed = text }))
			t.expect(p.action).toBe("refuse")
			t.expect(has(p.problems, "does not recognise")).toBe(true)
			t.expect(has(p.problems, "never overwrites one")).toBe(true)
		end
	end)

	it("a link or anything that is not a regular file is refused", function()
		for _, kind in { "link", "other" } do
			local p = hooks.plan(state({ kind = kind, installed = nil }))
			t.expect(`{kind} {p.action}`).toBe(`{kind} refuse`)
			t.expect(has(p.problems, "replaces only its own regular file")).toBe(true)
		end
	end)

	it(
		"a git configuration that moves the hooks folder is refused even for an exact copy, naming where it is set",
		function()
			local p = hooks.plan(state({ redirects = { { scope = "global", path = "/elsewhere" } } }))
			t.expect(p.action).toBe("refuse")
			t.expect(has(p.problems, "git reads hooks from /elsewhere (global configuration)")).toBe(true)
			t.expect(has(p.problems, `so {DEST} would never run`)).toBe(true)
			t.expect(has(p.problems, "remove that setting from your global git configuration")).toBe(true)
		end
	)

	it(
		"origin/main without our hook yet has nothing to install or check, and that is not a failure",
		function()
			local bare = state({ kind = "absent", redirects = { { scope = "global", path = "/elsewhere" } } })
			bare.source = nil
			bare.installed = nil
			local p = hooks.plan(bare)
			t.expect(p.action).toBe("none")
			t.expect(p.problems).toEqual({
				`hooks: origin/main has no {NAME} yet, so there is nothing to install or check`,
			})
		end
	)

	it(
		"a copy without our marker is refused, and says whose it is; a tree with no copy has nothing to install",
		function()
			local unmarked =
				hooks.plan(state({ source = "#!/bin/sh\nexit 0\n", kind = "absent", installed = nil }))
			t.expect(unmarked.action).toBe("refuse")
			t.expect(has(unmarked.problems, `origin/main's {NAME} is missing or has no`)).toBe(true)
			local bare = state({ from = "tree", kind = "absent" })
			bare.source = nil
			bare.installed = nil
			local without = hooks.plan(bare)
			t.expect(without.action).toBe("refuse")
			t.expect(has(without.problems, `this tree's {NAME} is missing or has no`)).toBe(true)
		end
	)

	it("every problem is reported, not only the first", function()
		local p = hooks.plan(state({
			kind = "link",
			installed = nil,
			redirects = { { scope = "local", path = "/a" }, { scope = "global", path = "/b" } },
		}))
		t.expect(p.action).toBe("refuse")
		t.expect(#p.problems).toBe(3)
	end)

	it(
		"redirects is the one setting git follows: the last value, unless it is the fence's or the own folder",
		function()
			local own = "/repo/.git/hooks"
			local function of(lines: { string }): { hooks.Redirect }
				return hooks.redirects(table.concat(lines, "\n") .. "\n", own)
			end
			t.expect(of({ "global\t/shared/hooks" }))
				.toEqual({ { scope = "global", path = "/shared/hooks" } })
			t.expect(of({ "global\t/shared/hooks", "local\t/mine" }))
				.toEqual({ { scope = "local", path = "/mine" } })
			-- a global value that a local one sets back to the own folder is no redirect
			t.expect(of({ "global\t/shared/hooks", "local\t/repo/.git/hooks" })).toEqual({})
			-- the fence's own setting (command scope) is not the person's, whatever else is set
			t.expect(of({ "command\t/fence/git-hooks" })).toEqual({})
			t.expect(of({ "global\t/shared/hooks", "command\t/fence/git-hooks" })).toEqual({
				{ scope = "global", path = "/shared/hooks" },
			})
			t.expect(of({ "junk with no tab", "" })).toEqual({})
			t.expect(hooks.redirects("", own)).toEqual({})
		end
	)

	it("isOurs wants the marker as a whole line", function()
		t.expect(hooks.isOurs(SOURCE)).toBe(true)
		t.expect(hooks.isOurs("#!/bin/sh\n" .. hooks.MARKER)).toBe(true)
		t.expect(hooks.isOurs(`# {hooks.MARKER}\n`)).toBe(false)
		t.expect(hooks.isOurs("")).toBe(false)
	end)
end)
