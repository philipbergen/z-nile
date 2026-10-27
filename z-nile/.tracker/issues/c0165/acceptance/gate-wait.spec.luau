--!strict
-- c0165 AC5 (claims, waits and owners): two runs of the same specs run each once and both report every result, a
-- failure included; a killed owner's spec is taken over and its runner dies with it, whether its pid or its whole
-- process group was killed (the lifeline); a wait on a live owner gives up after PICKMAN_REUSE_WAIT; a claimed spec
-- with no result counts failed. Every overlap is made by markers (gatefix.together, gatefix.owner), never by sleeps.
-- Fixtures under .cache/c0165-gate-wait.
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-wait`
local has, count, ran = gatefix.has, gatefix.count, gatefix.ran
local HANG = { "--", "tests/unit/hang.spec.luau" }

return t.spec("c0165 claims, waits and owners", function(it)
	it(
		"AC5: two concurrent runs in two worktrees run each spec once, and both report every result",
		function()
			local dir = gatefix.make(base, "concurrent")
			gatefix.worktree(dir, `{base}/concurrent-wt`)
			local p = gatefix.together(dir, `{base}/concurrent-wt`, {
				"--",
				"tests/unit/slow1.spec.luau",
				"tests/unit/slow2.spec.luau",
			})
			t.expect(count(ran(dir), "slow1")).toBe(1)
			t.expect(count(ran(dir), "slow2")).toBe(1)
			t.expect(p.rc1).toBe("0")
			t.expect(p.rc2).toBe("0")
			t.expect(has(p.out1, "2 passed, 0 failed, 2 spec files")).toBe(true)
			t.expect(has(p.out2, "2 passed, 0 failed, 2 spec files")).toBe(true)
			t.expect(has(p.out1 .. p.out2, "waited for pid")).toBe(true)
		end
	)

	it("AC5: a waiter whose owner's spec fails counts the failure, and the spec ran once", function()
		local dir = gatefix.make(base, "waitfail", { extra = { slowfail = { hold = true, broken = true } } })
		gatefix.worktree(dir, `{base}/waitfail-wt`)
		local p = gatefix.together(dir, `{base}/waitfail-wt`, { "--", "tests/unit/slowfail.spec.luau" })
		t.expect(count(ran(dir), "slowfail")).toBe(1)
		t.expect(p.rc1).toBe("1")
		t.expect(p.rc2).toBe("1")
		t.expect(has(p.out1 .. p.out2, "failed in pid")).toBe(true)
	end)

	it(
		"AC5: a killed owner group: its runner dies with it (the lifeline), and the next run takes the spec over",
		function()
			local dir = gatefix.make(base, "killed")
			local o = gatefix.owner(dir, "tests/unit/hang.spec.luau")
			-- the orchestrator's whole process group, with SIGKILL: nothing in it can clean up
			gatefix.killGroup(o.group)
			-- the runner still holds in its spec (hang.marker and C0165_HOLD are still set): only the lifeline can end it
			t.expect(gatefix.goneWithin(o.runner, 8)).toBe(true)
			local ok, out = gatefix.specs(dir, HANG)
			fs.removeFile(`{dir}/hang.marker`)
			t.expect(ok).toBe(true)
			t.expect(count(ran(dir), "hang")).toBe(2)
			t.expect(has(out, "1 passed, 0 failed, 1 spec files")).toBe(true)
			t.expect(has(out, "gave up waiting")).toBe(false)
		end
	)

	it(
		"AC5: a killed orchestrator (its pid alone): its runner dies with it, and the next run takes the spec over",
		function()
			local dir = gatefix.make(base, "orphan")
			local o = gatefix.owner(dir, "tests/unit/hang.spec.luau")
			-- only the orchestrator, the pid its db row names (not the group, not a rokit shim's pid)
			local owner = gatefix.sql(dir, "select owner_pid from specs where state = 'running'")
			t.expect(owner ~= "").toBe(true)
			process.exec("kill", { "-9", owner })
			t.expect(gatefix.goneWithin(o.runner, 8)).toBe(true)
			local ok, out = gatefix.specs(dir, HANG)
			fs.removeFile(`{dir}/hang.marker`)
			gatefix.killGroup(o.group)
			t.expect(ok).toBe(true)
			t.expect(count(ran(dir), "hang")).toBe(2)
			t.expect(has(out, "1 passed, 0 failed, 1 spec files")).toBe(true)
		end
	)

	it(
		"AC5: a wait on a live owner gives up after PICKMAN_REUSE_WAIT, runs the spec unclaimed and records nothing",
		function()
			local dir = gatefix.make(base, "timeout")
			local o = gatefix.owner(dir, "tests/unit/hang.spec.luau")
			-- the waiter has no C0165_HOLD, so its own run of hang.spec returns at once
			local ok, out = gatefix.specs(dir, HANG, { PICKMAN_REUSE_WAIT = "2" })
			local row = gatefix.sql(
				dir,
				"select state || ' ' || owner_pid from specs where spec = 'tests/unit/hang.spec.luau'"
			)
			fs.removeFile(`{dir}/hang.marker`)
			gatefix.killGroup(o.group)
			t.expect(ok).toBe(true)
			t.expect(has(out, "waiting for pid")).toBe(true)
			t.expect(count(ran(dir), "hang")).toBe(2)
			-- the pid the waiter gave up on is the owner the db records (not `$!`: a rokit shim runs the real lune as its
			-- child), and the owner's row is still its own: the waiter recorded nothing over it
			local gaveUp = string.match(out, "gave up waiting for pid (%d+)")
			t.expect(gaveUp ~= nil).toBe(true)
			t.expect(row).toBe(`running {gaveUp}`)
		end
	)

	it("AC5: a claimed spec with no result (the runner quit early) is released and counted failed", function()
		local dir = gatefix.make(base, "quitter", { extra = { quitter = { quits = true } } })
		local ok, out = gatefix.specs(
			dir,
			{ "--", "tests/unit/a.spec.luau", "tests/unit/quitter.spec.luau" },
			{ PICKMAN_JOBS = "1" }
		)
		t.expect(ok).toBe(false)
		t.expect(has(out, "results file missing")).toBe(true)
		t.expect(gatefix.sql(dir, "select count(*) from specs")).toBe("0")
	end)

	it("AC5: the runner's output is forwarded while it runs, not held until it ends", function()
		local dir =
			gatefix.make(base, "live", { extra = { afail = { broken = true }, bhold = { hold = true } } })
		fs.writeFile(`{dir}/hold.marker`, "")
		-- one job, path order: afail fails at once, then bhold holds; afail's FAIL line must be out while bhold holds
		local r = process.exec("bash", {
			"-c",
			'd=$1; (cd "$d"; PICKMAN_JOBS=1 PATH="$d/bin:$PATH" lune run z-nile/specs -- run --project pickman -- tests/unit/afail.spec.luau tests/unit/bhold.spec.luau > "$d/../live.out" 2>&1) & '
				.. 'seen=1; for i in $(seq 1 300); do grep -q "FAIL tests/unit/afail.spec.luau" "$d/../live.out" 2>/dev/null && { seen=0; break; }; sleep 0.1; done; '
				.. 'rm -f "$d/hold.marker"; wait; exit $seen',
			"_",
			dir,
		}, { env = { PICKMAN_OPEN_GUARD = "" } })
		-- 0: seen within 30 s, while bhold still held (its hold lasts up to 60 s, so held output would show only after);
		-- 1: not seen in that time
		t.expect(r.code).toBe(0)
		t.expect(count(ran(dir), "bhold")).toBe(1)
	end)
end)
