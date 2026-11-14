-- c0265 split: cases of beat.spec (monolithic version) that belong to c0274. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../beat.spec.orig. They never ran against an implementation.



	it(
		"a checkout that does not hold the claim refuses a bare beat, and the dispatcher's form is bound to the stamp it read",
		function()
			must(zn(wt, { "status", "c0095", "preparing" }, T0 + 1400), "claim c0095 in the worktree")
			local stamp = stampOf("c0095", `{P}/c0095/c0095.md`)
			local before = beats()
			-- the main checkout never adopted c0095, so it holds no claim memory for it: a bare beat would adopt whatever stamp origin has
			local bare = zn(h.f.main, { "beat", "c0095" }, T0 + 1500)
			t.expect(bare.ok).toBe(false)
			t.expect(has(bare.stderr, "does not hold")).toBe(true)
			t.expect(has(bare.stderr, "--adopt")).toBe(true)
			-- the dispatcher's form names the stamp it read at the step's start; a restamped item is refused, not beaten
			local stale = zn(
				h.f.main,
				{ "beat", "c0095", "--adopt", "--stamp", "preparing-silver-otter-quiet" },
				T0 + 1500
			)
			t.expect(stale.ok).toBe(false)
			t.expect(has(stale.stderr, `c0095's claim was taken over (now {stamp})`)).toBe(true)
			t.expect(#beats()).toBe(#before)
			for i, b in beats() do
				t.expect(b.sha).toBe(before[i].sha) -- nothing was written
			end
			-- and with the right stamp it beats
			must(
				zn(h.f.main, { "beat", "c0095", "--adopt", "--stamp", stamp }, T0 + 1500),
				"the dispatcher's form"
			)
		end
	)

	it("a main-checkout adoption writes no memory, so a re-claim does not make it refuse", function()
		must(zn(h.f.main, { "beat", "c0095", "--adopt" }, T0 + 1600), "main adopts c0095")
		t.expect(fs.isFile(`{h.f.main}/.cache/tracker-stamp-c0095`)).toBe(false)
		local first = stampOf("c0095", `{P}/c0095/c0095.md`)
		must(zn(wt, { "status", "c0095", "new" }, T0 + 1700), "give c0095 back")
		must(zn(wt, { "status", "c0095", "preparing" }, T0 + 1800), "claim c0095 again")
		local second = stampOf("c0095", `{P}/c0095/c0095.md`)
		t.expect(second ~= first).toBe(true)
		must(zn(h.f.main, { "beat", "c0095", "--adopt" }, T0 + 1900), "main adopts the new claim")
		local found = false
		for _, b in beats() do
			found = found or (b.stamp == second and b.epoch == T0 + 1900)
		end
		t.expect(found).toBe(true)
	end)
