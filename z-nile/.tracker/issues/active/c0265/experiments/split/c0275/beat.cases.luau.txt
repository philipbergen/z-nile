-- c0265 split: cases of beat.spec (monolithic version) that belong to c0275. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../beat.spec.orig. They never ran against an implementation.



	it("a claim writes the first beat as a branch, and main only gets the claim", function()
		local main = fixture.git(h.f.origin, { "rev-parse", "main" })
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		local stamp = stampOf("c0010", `{P}/c0010/c0010.md`)
		local list = beats()
		t.expect(#list).toBe(1)
		t.expect(list[1].stamp).toBe(stamp)
		t.expect(list[1].epoch).toBe(T0)
		-- the claim is one commit on main and the beat is not: the beat is one branch whose commit changes nothing
		t.expect(fixture.git(h.f.origin, { "rev-list", "--count", `{main}..main` })).toBe("1")
		t.expect(fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", "refs/heads/" }))
			.toBe(`refs/heads/hb/{stamp}\nrefs/heads/main`)
		local tip = `refs/heads/hb/{stamp}`
		t.expect(fixture.git(h.f.origin, { "rev-parse", tip .. "^{tree}" }))
			.toBe(fixture.git(h.f.origin, { "rev-parse", "main^{tree}" }))
		t.expect(fixture.git(h.f.origin, { "rev-parse", tip .. "^" }))
			.toBe(fixture.git(h.f.origin, { "rev-parse", "main" }))
		t.expect(fixture.git(h.f.origin, { "log", "-1", "--format=%s", tip })).toBe(`hb {stamp} {T0}`)
		-- ./zn busy sees no change on it
		t.expect(has(zn(h.f.main, { "busy", "z-nile", "pickman" }, T0).stdout, "hb/")).toBe(false)
	end)

	it("ready beats for the raft it claims", function()
		must(zn(h.f.main, { "ready", "R0010" }, T0), "ready R0010")
		local stamp = stampOf("R0010", "pickman/.tracker/rafts/active/R0010/R0010.md")
		local found = false
		for _, b in beats() do
			found = found or (b.stamp == stamp and b.epoch == T0)
		end
		t.expect(found).toBe(true)
		t.expect(string.sub(stamp, 1, 7)).toBe("active-")
	end)

	it("any ./zn command in a worktree that holds a claim beats it once an interval has passed", function()
		local stamp = stampOf("c0010", `{P}/c0010/c0010.md`)
		local function mine(): { number }
			local out = {}
			for _, b in beats() do
				if b.stamp == stamp then
					table.insert(out, b.epoch)
				end
			end
			return out
		end
		must(zn(wt, { "status", "c0010" }, T0 + 1000), "status in the worktree") -- its last beat from here: T0
		t.expect(mine()).toEqual({ T0 + 1000 })
		must(zn(wt, { "status", "c0010" }, T0 + 1100), "status again, inside the interval")
		t.expect(mine()).toEqual({ T0 + 1000 }) -- no second push inside the interval
		-- the main checkout holds no work: a command there beats nothing, however old the last beat
		must(zn(h.f.main, { "status", "c0010" }, T0 + 5000), "status in the main checkout")
		t.expect(mine()).toEqual({ T0 + 1000 })
	end)

	it("new raft beats for the raft it claims", function()
		must(
			zn(wt, { "new", "raft", "chore", "beatraft", "c0020", "--project", "pickman" }, T0 + 1300),
			"new raft"
		)
		local listing = zn(h.f.main, { "status" }, T0 + 1300).stdout
		local rid = string.match(listing, "(R%d+) preparing") or error("no new raft in the status list")
		local stamp = stampOf(rid, `pickman/.tracker/rafts/{rid}/{rid}.md`)
		local found = false
		for _, b in beats() do
			found = found or (b.stamp == stamp and b.epoch == T0 + 1300)
		end
		t.expect(found).toBe(true)
	end)

	it("a nested ./zn in a protected checkout never beats", function()
		local entry = `{wt}/.cache/tracker-beats/c0010`
		local before = #beats()
		local entryBefore = fs.readFile(entry)
		local function net(): number
			local text = if fs.isFile(`{h.fakes}/netcalls`) then fs.readFile(`{h.fakes}/netcalls`) else ""
			return #string.gsub(text, "[^x]", "")
		end
		local netBefore = net()
		-- the fence's own spelling: the canonical git common directory, appended to what the runner already lists
		local common = string.gsub(
			fixture.git(h.f.main, { "rev-parse", "--path-format=absolute", "--git-common-dir" }),
			"%s+$",
			""
		)
		local inherited = process.env.PICKMAN_FENCE_REAL_GIT or ""
		local listed = if inherited ~= "" then `{inherited}:{common}` else common
		must(
			zn(wt, { "lessons", "--tags" }, T0 + 9000, { PICKMAN_FENCE_REAL_GIT = listed }),
			"a nested command"
		)
		t.expect(#beats()).toBe(before)
		t.expect(fs.readFile(entry)).toBe(entryBefore) -- not even a failed attempt: the entry is untouched
		-- the explicit command refuses there too, naming the rule (the fence's pre-push hook is only the second line)
		local explicit = zn(wt, { "beat", "c0010" }, T0 + 9000, { PICKMAN_FENCE_REAL_GIT = listed })
		t.expect(explicit.ok).toBe(false)
		t.expect(has(explicit.stderr, "protected")).toBe(true)
		t.expect(#beats()).toBe(before)
		-- every heartbeat path asks the guard before its first network call: neither the autobeat nor the explicit
		-- beat fetched, listed or pushed anything
		t.expect(net()).toBe(netBefore)
	end)
