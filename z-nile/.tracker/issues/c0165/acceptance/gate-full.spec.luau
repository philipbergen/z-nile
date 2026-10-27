--!strict
-- c0165 AC7 (the full gate and the merge condition): `--full` runs every spec whatever was recorded, `--full --reuse`
-- skips only on a full gate's own record of the same content digest (done's uncommitted tree included, spend.md the one
-- tracker file that may change after it), a gate-check that answers without its `reused` line never skips, and a gate
-- whose tree changes while it runs records nothing. Fixtures under .cache/c0165-gate-full (gatefix.luau).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-full`
local has, count, ran, clearRan, write =
	gatefix.has, gatefix.count, gatefix.ran, gatefix.clearRan, gatefix.write

return t.spec("c0165 the full gate and the merge condition", function(it)
	it(
		"AC7: --full runs every spec despite recorded passes; --full --reuse needs a full record of the same content",
		function()
			local dir = gatefix.make(base, "full")
			-- an affected gate passes and records every spec it ran
			local ok0, _ = gatefix.specs(dir, { "--all" })
			t.expect(ok0).toBe(true)
			local ok0g, _ = gatefix.gate(dir, { "--affected" })
			t.expect(ok0g).toBe(true)
			-- an affected record never stands in for a full one
			clearRan(dir)
			local ok1, out1 = gatefix.gate(dir, { "--full", "--reuse" })
			t.expect(ok1).toBe(true)
			t.expect(has(out1, "GATE PASSED (full)")).toBe(true)
			for _, n in { "a", "b", "text", "slow1", "slow2", "hang" } do
				t.expect(count(ran(dir), n)).toBe(1)
			end
			-- plain --full runs everything again, even though every fingerprint passed
			clearRan(dir)
			local ok2, _ = gatefix.gate(dir, { "--full" })
			t.expect(ok2).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "hang")).toBe(1)
			-- now a full record exists: --full --reuse runs nothing
			clearRan(dir)
			local ok3, out3 = gatefix.gate(dir, { "--full", "--reuse" })
			t.expect(ok3).toBe(true)
			t.expect(has(out3, "reused: a full gate passed on this content")).toBe(true)
			t.expect(has(out3, "GATE PASSED (full)")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- a gate-check that answers 0 without its `reused` line (a stub, a wrapper) never skips the gate
			write(
				`{dir}/bin-silent/lune`,
				'#!/bin/sh\nif [ "$1" = run ] && [ "$2" = z-nile/specs ] && [ "$4" = gate-check ]; then exit 0; fi\n'
					.. `exec "{dir}/bin/lune" "$@"\n`
			)
			process.exec("chmod", { "+x", `{dir}/bin-silent/lune` })
			local okS, outS = gatefix.gate(
				dir,
				{ "--full", "--reuse" },
				{ PATH = `{dir}/bin-silent:{dir}/bin:{process.env.PATH or ""}` }
			)
			t.expect(okS).toBe(true)
			t.expect(has(outS, "reused: a full gate passed on this content")).toBe(false)
			t.expect(count(ran(dir), "a")).toBe(1)
			clearRan(dir)
			-- an untracked file changes the content: it runs again
			write(`{dir}/pickman/notes.txt`, "new\n")
			local ok4, _ = gatefix.gate(dir, { "--full", "--reuse" })
			t.expect(ok4).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			fs.removeFile(`{dir}/pickman/notes.txt`)
			-- committing the same content keeps the record: the digest is content, not a commit
			clearRan(dir)
			fixture.git(dir, { "commit", "-q", "--allow-empty", "-m", "empty" })
			local ok5, out5 = gatefix.gate(dir, { "--full", "--reuse" })
			t.expect(ok5).toBe(true)
			t.expect(has(out5, "reused: a full gate passed on this content")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- conflicting flags refuse
			local ok6, _ = gatefix.gate(dir, { "--affected", "--reuse" })
			t.expect(ok6).toBe(false)
			local ok7, _ = gatefix.gate(dir, { "--full", "--fresh" })
			t.expect(ok7).toBe(false)
		end
	)
	it("AC7: a gate whose tree changes while it runs records no whole-gate pass, affected or full", function()
		local dir = gatefix.make(
			base,
			"dirty",
			{ extra = { dirty = { needs = "A", writes = { path = "notes-dirty.txt", text = "dirty\\n" } } } }
		)
		local note = `{dir}/pickman/notes-dirty.txt`
		local function unnote()
			if fs.isFile(note) then
				fs.removeFile(note)
			end
		end
		write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n") -- selects dirty.spec and a.spec
		-- dirty.spec writes an untracked file while the gate runs: the digest moves, so no gates row
		local ok1, _ = gatefix.gate(dir, { "--affected" })
		t.expect(ok1).toBe(true)
		t.expect(fs.isFile(note)).toBe(true)
		unnote()
		local ok2, out2 = gatefix.gate(dir, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(false)
		unnote()
		-- the full gate: record --full finds the digest moved, records no row, and says so
		local okF, outF = gatefix.gate(dir, { "--full" })
		t.expect(okF).toBe(true)
		t.expect(has(outF, "records nothing")).toBe(true)
		local rows = gatefix.sql(
			dir,
			"select count(*) from specs where spec = 'tests/unit/dirty.spec.luau' and state = 'passed'"
		)
		-- the one affected-mode row from the first gate (dirty.spec's own inputs didn't change); none from the full gate
		t.expect(rows).toBe("1")
		unnote()
		local okR, outR = gatefix.gate(dir, { "--full", "--reuse" })
		t.expect(okR).toBe(true)
		t.expect(has(outR, "reused: a full gate passed on this content")).toBe(false)
	end)
	it(
		"AC7: done's uncommitted tree (staged moves and edits) is reused on the committed head; spend.md may change, nothing else",
		function()
			local dir = gatefix.make(base, "donetree", {
				setup = function(d: string)
					write(`{d}/pickman/docs/a.md`, "a\n")
					write(`{d}/pickman/.tracker/issues/f0009/f0009.md`, "# f0009\n")
				end,
			})
			fixture.git(dir, { "mv", "pickman/docs/a.md", "pickman/docs/b.md" })
			write(`{dir}/pickman/src/B.luau`, "return { value = 1 } -- staged\n")
			fixture.git(dir, { "add", "pickman/src/B.luau" })
			local ok1, _ = gatefix.gate(dir, { "--full" })
			t.expect(ok1).toBe(true)
			-- what done does after its gate: spend rows, then the commit of everything
			write(`{dir}/pickman/.tracker/issues/f0009/spend.md`, "# spend\n| phase | minutes |\n")
			fixture.git(dir, { "add", "-A" })
			fixture.git(dir, { "commit", "-qm", "done" })
			clearRan(dir)
			local ok2, out2 = gatefix.gate(dir, { "--full", "--reuse" })
			t.expect(ok2).toBe(true)
			t.expect(has(out2, "reused: a full gate passed on this content")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- any other tracker document is content: it runs again
			write(`{dir}/pickman/.tracker/issues/f0009/f0009.md`, "# f0009 edited\n")
			fixture.git(dir, { "commit", "-qam", "edit" })
			local ok3, out3 = gatefix.gate(dir, { "--full", "--reuse" })
			t.expect(ok3).toBe(true)
			t.expect(has(out3, "reused: a full gate passed on this content")).toBe(false)
			t.expect(count(ran(dir), "a")).toBe(1)
		end
	)
end)
