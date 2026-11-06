--!strict
-- c0165 AC7 (the full gate and the whole-gate record): `--full` runs every spec whatever was recorded and prints no
-- `reused` line, `--full` with `--fresh` is refused with exit 2, and an affected gate whose tree changes while it runs
-- records no whole-gate pass. What `--full` does to the db (today nothing; c0239 records it for `--full --reuse`) is not
-- pinned here: proof-interim.luau checks today's facts once, at c0165's done. Fixtures under .cache/c0165-gate-full
-- (gatefix.luau).
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-full`
local has, count, ran, clearRan, write =
	gatefix.has, gatefix.count, gatefix.ran, gatefix.clearRan, gatefix.write

return t.spec("c0165 the full gate and the whole-gate record", function(it)
	it("AC7: --full runs every spec despite recorded passes and reuses nothing", function()
		local dir = gatefix.make(base, "full")
		-- an affected gate passes and records every spec it ran
		local ok0, _ = gatefix.specs(dir, { "--all" })
		t.expect(ok0).toBe(true)
		local ok0g, _ = gatefix.gate(dir, { "--affected" })
		t.expect(ok0g).toBe(true)
		-- plain --full runs everything again, even though every fingerprint passed
		clearRan(dir)
		local ok1, out1 = gatefix.gate(dir, { "--full" })
		t.expect(ok1).toBe(true)
		t.expect(has(out1, "GATE PASSED (full)")).toBe(true)
		t.expect(has(out1, "reused")).toBe(false)
		for _, n in { "a", "b", "text", "slow1" } do
			t.expect(count(ran(dir), n)).toBe(1)
		end
	end)

	it("AC7: --fresh is an affected flag: with --full the gate refuses it with exit 2", function()
		local dir = gatefix.make(base, "fresh")
		local code, out = gatefix.gateStatus(dir, { "--full", "--fresh" })
		t.expect(code).toBe(2)
		t.expect(has(out, "unknown or conflicting flags")).toBe(true)
		t.expect(has(out, "GATE PASSED")).toBe(false)
		t.expect(ran(dir)).toBe("")
	end)

	it("AC7: an affected gate whose tree changes while it runs records no whole-gate pass", function()
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
		t.expect(gatefix.sql(dir, "select count(*) from gates")).toBe("0")
		unnote()
		local ok2, out2 = gatefix.gate(dir, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(false)
		unnote()
	end)
end)
