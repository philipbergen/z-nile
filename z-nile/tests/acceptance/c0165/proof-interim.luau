--!strict
-- c0165, run by check.sh before `./zn done` only (never a spec, never promoted as one): the two facts that are true of
-- the core today and that c0238 and c0239 change on purpose, so no promoted spec may pin them (design review 007 F3,
-- zz-test/promoted-specs-pin-rules-not-sets):
--   1. two runs that reach one fingerprint at once BOTH run it (c0238 makes the second wait for the first);
--   2. `check.sh --full` neither reads nor writes the results db (c0239 records a full run, for `--full --reuse`).
-- A failed expectation raises, so `lune run` exits non-zero. Fixtures under .cache/c0165-proof-interim.
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-proof-interim`

return t.spec("c0165 interim facts", function(it)
	it("two runs that reach one fingerprint at once both run it", function()
		-- 1. both ran: the marker is removed only once slow1 has started twice (strict), so the runs overlapped
		do
			local dir = gatefix.make(base, "pair")
			local other = `{base}/pair-wt`
			gatefix.worktree(dir, other)
			local pair = gatefix.together(dir, other, "slow1", { "--", "tests/unit/slow1.spec.luau" }, true)
			t.expect(pair.rc1).toBe("0")
			t.expect(pair.rc2).toBe("0")
			t.expect(gatefix.count(gatefix.ran(dir), "slow1")).toBe(2)
			t.expect(gatefix.sql(dir, "select count(*) from specs where spec = 'tests/unit/slow1.spec.luau'"))
				.toBe("1")
		end
	end)

	it("--full leaves the db as it was and reads no row", function()
		do
			local dir = gatefix.make(base, "full")
			local ok0, _ = gatefix.specs(dir, { "--all" })
			t.expect(ok0).toBe(true)
			local ok0g, _ = gatefix.gate(dir, { "--affected" })
			t.expect(ok0g).toBe(true)
			local rows = gatefix.sql(dir, "select count(*) from specs")
			local gates = gatefix.sql(dir, "select count(*) from gates")
			t.expect(rows ~= "0").toBe(true)
			gatefix.clearRan(dir)
			local ok1, out1 = gatefix.gate(dir, { "--full" })
			t.expect(ok1).toBe(true)
			t.expect(gatefix.has(out1, "reused")).toBe(false)
			t.expect(gatefix.sql(dir, "select count(*) from specs")).toBe(rows)
			t.expect(gatefix.sql(dir, "select count(*) from gates")).toBe(gates)
		end
	end)
end)
