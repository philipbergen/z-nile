--!strict
-- c0165 AC7 (the whole affected gate, through `z-nile/check.sh --affected` in fixture repositories, gatefix.luau): an
-- unchanged second gate is reused with its static report, a record is scoped by its projects and its base, and a
-- gate-check that never claims reuse never skips the gate. Fixtures under .cache/c0165-gate-whole.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-whole`
local has, count, ran, clearRan, write =
	gatefix.has, gatefix.count, gatefix.ran, gatefix.clearRan, gatefix.write

return t.spec("c0165 the whole affected gate", function(it)
	it(
		"AC7: through check.sh --affected: the edit's selection runs, and an unchanged second gate is reused whole, its static report shown",
		function()
			local dir = gatefix.make(base, "affected")
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local ok1, out1 = gatefix.gate(dir, { "--affected" })
			t.expect(ok1).toBe(true)
			t.expect(has(out1, "GATE PASSED (affected)")).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(0)
			clearRan(dir)
			local ok2, out2 = gatefix.gate(dir, { "--affected" })
			t.expect(ok2).toBe(true)
			t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(true)
			-- the static stages' report is shown from the record (the lint summary zz-execute Phase 4 reads)
			t.expect(has(out2, "== lint (selene)")).toBe(true)
			t.expect(has(out2, "GATE PASSED (affected)")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- --fresh runs the selection again
			local ok3, _ = gatefix.gate(dir, { "--affected", "--fresh" })
			t.expect(ok3).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
		end
	)

	it("AC7: a whole-gate record is scoped by its projects and its base", function()
		local dir = gatefix.make(base, "scope")
		write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		fixture.git(dir, { "commit", "-qam", "edit" })
		local ok1, _ = gatefix.gate(dir, { "--affected" })
		t.expect(ok1).toBe(true)
		local ok2, out2 = gatefix.gate(dir, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(true)
		-- no --project, but only pickman changed: the static stages narrow to pickman, so it is the same gate
		local okAll, outAll = gatefix.gateRaw(dir, { "--affected" })
		t.expect(okAll).toBe(true)
		t.expect(has(outAll, "reused: an affected gate passed on this content")).toBe(true)
		-- another project's record does not stand for pickman's
		local okZn, outZn = gatefix.gateRaw(dir, { "--project", "z-nile", "--affected" })
		t.expect(okZn).toBe(true)
		t.expect(has(outZn, "reused: an affected gate passed on this content")).toBe(false)
		-- another base: the same content, compared with another commit, is another selection and another gate
		local okBase, outBase = gatefix.gate(dir, { "--affected", "--base", "HEAD" })
		t.expect(okBase).toBe(true)
		t.expect(has(outBase, "reused: an affected gate passed on this content")).toBe(false)
	end)

	it("AC7: a gate-check that answers 0 without its reused line never skips the gate", function()
		local dir = gatefix.make(base, "silent")
		write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		local ok1, _ = gatefix.gate(dir, { "--affected" })
		t.expect(ok1).toBe(true)
		-- first, unstubbed: the second gate on this content IS reused, so the stub below is tested against a real skip
		local okReal, outReal = gatefix.gate(dir, { "--affected" })
		t.expect(okReal).toBe(true)
		t.expect(has(outReal, "reused: an affected gate passed on this content")).toBe(true)
		-- a stub or wrapper whose gate-check exits 0 and prints nothing: the gate still runs its stages
		write(
			`{dir}/bin-silent/lune`,
			'#!/bin/sh\nif [ "$1" = run ] && [ "$2" = z-nile/specs ] && [ "$4" = gate-check ]; then echo called >> "'
				.. `{dir}/silent.out"; exit 0; fi\n`
				.. `exec "{dir}/bin/lune" "$@"\n`
		)
		process.exec("chmod", { "+x", `{dir}/bin-silent/lune` })
		local ok2, out2 = gatefix.gate(
			dir,
			{ "--affected" },
			{ PATH = `{dir}/bin-silent:{dir}/bin:{process.env.PATH or ""}` }
		)
		t.expect(ok2).toBe(true)
		-- the stub was reached (the gate asked), and its silence did not skip anything
		t.expect(fs.isFile(`{dir}/silent.out`)).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(false)
		t.expect(has(out2, "== lint (selene)")).toBe(true)
		t.expect(has(out2, "GATE PASSED (affected)")).toBe(true)
	end)
end)
