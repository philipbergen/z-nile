--!strict
-- c0165 AC5 (runs that record nothing, in fixture repositories, gatefix.luau): a weak jail (whose gate removes its own
-- marker and no other), reuse off (no sqlite3), a failed blob read, and a no-record marker in any picked home.
-- Fixtures under .cache/c0165-gate-norecord.
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-norecord`
local has, count, ran, write = gatefix.has, gatefix.count, gatefix.ran, gatefix.write
local AB = gatefix.AB

return t.spec("c0165 runs that record nothing", function(it)
	it("AC5: a weak-jail run records neither spec rows nor a whole-gate row", function()
		local affected = gatefix.make(base, "norecord-affected")
		write(`{affected}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		-- another concurrent gate's marker (another pid) sits in the same home
		write(`{affected}/pickman/.cache/spec-norecord-9999`, "")
		local weakA = { PATH = gatefix.weakJail(affected) }
		local ok1, out1 = gatefix.gate(affected, { "--affected" }, weakA)
		t.expect(ok1).toBe(true)
		t.expect(has(out1, "not recorded: outer sandbox (protects the repository)")).toBe(true)
		-- the gate removed the marker it wrote and only that one: the foreign marker survives it
		local left = {}
		for _, name in fs.readDir(`{affected}/pickman/.cache`) do
			if string.sub(name, 1, #"spec-norecord-") == "spec-norecord-" then
				table.insert(left, name)
			end
		end
		t.expect(left).toEqual({ "spec-norecord-9999" })
		t.expect(gatefix.sql(affected, "select count(*) from specs")).toBe("0")
		t.expect(gatefix.sql(affected, "select count(*) from gates")).toBe("0")
		local ok2, out2 = gatefix.gate(affected, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(false)
		t.expect(count(ran(affected), "a")).toBe(2)
	end)

	it("AC5: with reuse off (no sqlite3) every given spec runs and the result is unchanged", function()
		local dir = gatefix.make(base, "off")
		local miss = { PICKMAN_SQLITE3 = `{dir}/no-such-sqlite3` }
		local ok1, out1 = gatefix.specs(dir, AB, miss)
		t.expect(ok1).toBe(true)
		t.expect(has(out1, "reuse off:")).toBe(true)
		local ok2, _ = gatefix.specs(dir, AB, miss)
		t.expect(ok2).toBe(true)
		t.expect(count(ran(dir), "a")).toBe(2)
		t.expect(count(ran(dir), "b")).toBe(2)
		t.expect(fs.isFile(`{dir}/.claude/.znile_tests.sqlite`)).toBe(false)
		-- a failing spec still fails the run with reuse off
		write(`{dir}/pickman/src/A.luau`, "return { value = 2 }\n")
		local ok3, _ = gatefix.specs(dir, AB, miss)
		t.expect(ok3).toBe(false)
	end)

	it(
		"AC5: a failed blob read (hash-object) turns reuse off: every spec runs and nothing is recorded",
		function()
			local dir = gatefix.make(base, "gitfail")
			local realGit = gatefix.trim(process.exec("sh", { "-c", "command -v git" }).stdout)
			write(
				`{dir}/bin-gitfail/git`,
				'#!/bin/sh\nif [ "$1" = hash-object ]; then exit 1; fi\n' .. `exec "{realGit}" "$@"\n`
			)
			process.exec("chmod", { "+x", `{dir}/bin-gitfail/git` })
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local env1 = { PATH = `{dir}/bin-gitfail:{dir}/bin:{process.env.PATH or ""}` }
			local ok1, out1 = gatefix.specs(dir, AB, env1)
			t.expect(ok1).toBe(true)
			t.expect(has(out1, "reuse off:")).toBe(true)
			local ok2, _ = gatefix.specs(dir, AB, env1)
			t.expect(ok2).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(2)
			t.expect(count(ran(dir), "b")).toBe(2)
		end
	)

	it(
		"AC5: gate-record records nothing (and exits 0) while any picked home holds this gate's no-record marker, and records once it is gone",
		function()
			local dir = gatefix.make(base, "marker")
			local summary = `{dir}/summary.out`
			write(summary, "== lint (selene)\n")
			local function record(): boolean
				local r = process.exec("lune", {
					"run",
					"z-nile/specs",
					"--",
					"gate-record",
					"--digest",
					"d1",
					"--mode",
					"affected",
					"--projects",
					"pickman,z-nile",
					"--summary",
					summary,
				}, { cwd = dir, env = gatefix.env(dir, { PICKMAN_GATE_PID = "4242" }) })
				return r.ok
			end
			-- the orchestrator of z-nile's run wrote the marker (it alone knows that run's jail); pickman's home has none
			local marker = `{dir}/z-nile/.cache/spec-norecord-4242`
			write(marker, "")
			t.expect(record()).toBe(true)
			t.expect(gatefix.sql(dir, "select count(*) from gates")).toBe("0")
			-- another gate's marker (another pid) does not block this one
			fs.removeFile(marker)
			write(`{dir}/z-nile/.cache/spec-norecord-9999`, "")
			t.expect(record()).toBe(true)
			t.expect(gatefix.sql(dir, "select count(*) from gates where key = 'd1'")).toBe("1")
		end
	)
end)
