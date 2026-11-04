--!strict
-- c0165 AC5 (reuse through the orchestrator `z-nile/specs`, in fixture repositories, gatefix.luau): the same content
-- reuses every spec, an edit reruns only its specs, `--fresh` reruns, a second worktree reuses the first's pass, two runs
-- at once leave one passed row, an ordinary run prunes old rows. Fixtures under .cache/c0165-gate-reuse.
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-reuse`
local has, count, ran, clearRan, write =
	gatefix.has, gatefix.count, gatefix.ran, gatefix.clearRan, gatefix.write
local AB = gatefix.AB

return t.spec("c0165 reuse through the orchestrator", function(it)
	it(
		"AC5: a second run on the same content reuses every spec and runs none; an edit reruns only its specs",
		function()
			local dir = gatefix.make(base, "reuse")
			local ok1, out1 = gatefix.specs(dir, AB)
			t.expect(ok1).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(1)
			t.expect(has(out1, "2 passed, 0 failed, 2 spec files")).toBe(true)
			t.expect(fs.isFile(`{dir}/.claude/.znile_tests.sqlite`)).toBe(true)
			clearRan(dir)
			local ok2, out2 = gatefix.specs(dir, AB)
			t.expect(ok2).toBe(true)
			t.expect(ran(dir)).toBe("")
			t.expect(has(out2, "reused tests/unit/a.spec.luau")).toBe(true)
			t.expect(has(out2, "reused tests/unit/b.spec.luau")).toBe(true)
			t.expect(has(out2, "2 passed, 0 failed, 2 spec files")).toBe(true)
			-- an uncommitted edit of A: a reruns, b is reused
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local ok3, _ = gatefix.specs(dir, AB)
			t.expect(ok3).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(0)
			-- --fresh runs both again
			clearRan(dir)
			local ok4, _ = gatefix.specs(dir, { "--fresh", table.unpack(AB) })
			t.expect(ok4).toBe(true)
			t.expect(count(ran(dir), "a") + count(ran(dir), "b")).toBe(2)
		end
	)

	it(
		"AC5: a second worktree of the checkout reuses the first's pass (one db for every worktree)",
		function()
			local dir = gatefix.make(base, "shared")
			local ok1, _ = gatefix.specs(dir, AB)
			t.expect(ok1).toBe(true)
			clearRan(dir)
			local other = `{base}/shared-wt`
			gatefix.worktree(dir, other)
			local ok2, out2 = gatefix.specs(other, AB)
			t.expect(ok2).toBe(true)
			t.expect(has(out2, "reused tests/unit/a.spec.luau")).toBe(true)
			t.expect(has(out2, "reused tests/unit/b.spec.luau")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- the worktree made no db of its own
			t.expect(fs.isFile(`{other}/.claude/.znile_tests.sqlite`)).toBe(false)
		end
	)

	it("AC5: two runs that reach one fingerprint at once both succeed and leave one passed row", function()
		local dir = gatefix.make(base, "pair")
		local other = `{base}/pair-wt`
		gatefix.worktree(dir, other)
		local slow = { "--", "tests/unit/slow1.spec.luau" }
		local pair = gatefix.together(dir, other, "slow1", slow, false)
		-- the rule: both exit 0 with the file's result, and the db holds one passed row. Whether the second ran the spec or
		-- waited for the first is c0238's to change; proof-interim.luau checks today's behaviour once, at c0165's done
		t.expect(pair.rc1).toBe("0")
		t.expect(pair.rc2).toBe("0")
		t.expect(has(pair.out1, "1 passed, 0 failed, 1 spec files")).toBe(true)
		t.expect(has(pair.out2, "1 passed, 0 failed, 1 spec files")).toBe(true)
		t.expect(count(ran(dir), "slow1") >= 1).toBe(true)
		t.expect(gatefix.sql(dir, "select count(*) from specs where spec = 'tests/unit/slow1.spec.luau'"))
			.toBe("1")
		t.expect(gatefix.sql(dir, "select state from specs where spec = 'tests/unit/slow1.spec.luau'"))
			.toBe("passed")
	end)

	it(
		"AC5: an ordinary run prunes the rows and gates not updated for 30 days, and keeps the others",
		function()
			local dir = gatefix.make(base, "prune")
			local ok1, _ = gatefix.specs(dir, AB)
			t.expect(ok1).toBe(true)
			local now = "cast(strftime('%s', 'now') as integer)"
			gatefix.sqlWrite(
				dir,
				"insert into specs(fp, home, spec, state, updated) values "
					.. `('old-fp', 'pickman', 'tests/unit/old.spec.luau', 'passed', {now} - 31 * 86400), `
					.. `('young-fp', 'pickman', 'tests/unit/young.spec.luau', 'passed', {now} - 29 * 86400); `
					.. "insert into gates(key, mode, projects, passed_at, summary) values "
					.. `('old-gate', 'affected', 'pickman', {now} - 31 * 86400, 'x'), `
					.. `('young-gate', 'affected', 'pickman', {now} - 29 * 86400, 'x');`
			)
			-- an edit makes the next run record a new row: the ordinary run that prunes
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local ok2, _ = gatefix.specs(dir, AB)
			t.expect(ok2).toBe(true)
			t.expect(gatefix.sql(dir, "select count(*) from specs where fp in ('old-fp', 'young-fp')"))
				.toBe("1")
			t.expect(gatefix.sql(dir, "select fp from specs where fp in ('old-fp', 'young-fp')"))
				.toBe("young-fp")
			t.expect(gatefix.sql(dir, "select key from gates")).toBe("young-gate")
			-- what the run recorded is still there
			t.expect(gatefix.sql(dir, "select count(*) from specs where spec = 'tests/unit/a.spec.luau'"))
				.toBe("2")
		end
	)
end)
